{-# LANGUAGE OverloadedStrings #-}

module Krill.Parse
  ( ParseError (..),
    parseWorkflowBytes,
    parseWorkflowFile,
  )
where

import Control.Monad (unless)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Char (isSpace)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (decodeUtf8')
import Krill.Types (ApprovalGate (..), Step (..), Workflow (..))
import Text.Parsec
  ( anyChar,
    between,
    char,
    digit,
    eof,
    many,
    many1,
    noneOf,
    optionMaybe,
    parse,
    satisfy,
    sepBy,
    string,
    (<|>),
  )
import Text.Parsec.Text (Parser)

newtype ParseError = ParseError
  { parseErrorMessage :: Text
  }
  deriving (Eq, Show)

type ParseResult = Either ParseError

parseWorkflowFile :: FilePath -> IO (ParseResult Workflow)
parseWorkflowFile path = parseWorkflowBytes <$> BS.readFile path

parseWorkflowBytes :: ByteString -> ParseResult Workflow
parseWorkflowBytes raw = do
  content <- first (ParseError . T.pack . show) (decodeUtf8' raw)
  if looksLikeJson content
    then parseJsonWorkflow content
    else parseYamlWorkflow content

looksLikeJson :: Text -> Bool
looksLikeJson content =
  case T.uncons (T.dropWhile isSpace content) of
    Just ('{', _) -> True
    _ -> False

-- JSON parsing

data JValue
  = JObject [(Text, JValue)]
  | JArray [JValue]
  | JString Text
  | JNumber Int
  | JBool Bool
  | JNull
  deriving (Eq, Show)

parseJsonWorkflow :: Text -> ParseResult Workflow
parseJsonWorkflow content = do
  root <- first (ParseError . T.pack . show) (parse jsonDocument "workflow-json" content)
  case root of
    JObject pairs -> workflowFromJsonPairs pairs
    _ -> Left (ParseError "workflow JSON root must be an object")

jsonDocument :: Parser JValue
jsonDocument = spacesConsumer *> jsonValue <* spacesConsumer <* eof

jsonValue :: Parser JValue
jsonValue =
  jsonObject
    <|> jsonArray
    <|> (JString <$> jsonString)
    <|> (JNumber <$> jsonNumber)
    <|> (JBool True <$ string "true")
    <|> (JBool False <$ string "false")
    <|> (JNull <$ string "null")

jsonObject :: Parser JValue
jsonObject =
  JObject <$> between (symbol '{') (symbol '}') (jsonPair `sepBy` symbol ',')

jsonPair :: Parser (Text, JValue)
jsonPair = do
  key <- jsonString
  _ <- symbol ':'
  value <- jsonValue
  pure (key, value)

jsonArray :: Parser JValue
jsonArray = JArray <$> between (symbol '[') (symbol ']') (jsonValue `sepBy` symbol ',')

jsonString :: Parser Text
jsonString = do
  _ <- char '"'
  chars <- many (escapedChar <|> noneOf ['"'])
  _ <- char '"'
  spacesConsumer
  pure (T.pack chars)

escapedChar :: Parser Char
escapedChar = do
  _ <- char '\\'
  escape <- anyChar
  pure $ case escape of
    '"' -> '"'
    '\\' -> '\\'
    '/' -> '/'
    'n' -> '\n'
    'r' -> '\r'
    't' -> '\t'
    other -> other

jsonNumber :: Parser Int
jsonNumber = do
  sign <- optionMaybe (char '-')
  digits <- many1 digit
  spacesConsumer
  let value = read digits
  pure $ case sign of
    Just _ -> negate value
    Nothing -> value

spacesConsumer :: Parser ()
spacesConsumer = do
  _ <- many (satisfy isSpace)
  pure ()

symbol :: Char -> Parser Char
symbol c = spacesConsumer *> char c <* spacesConsumer

workflowFromJsonPairs :: [(Text, JValue)] -> ParseResult Workflow
workflowFromJsonPairs pairs = do
  workflowName <- requiredText "name" pairs
  workflowVersion <- fromMaybe 1 <$> optionalInt "version" pairs
  stepsValue <- requiredValue "steps" pairs
  workflowSteps <-
    case stepsValue of
      JArray values -> mapM stepFromJsonValue values
      _ -> Left (ParseError "workflow.steps must be an array")

  unless (workflowVersion > 0) (Left (ParseError "workflow.version must be positive"))
  unless (not (null workflowSteps)) (Left (ParseError "workflow.steps must contain at least one step"))

  pure
    Workflow
      { workflowName = workflowName,
        workflowVersion = workflowVersion,
        workflowSteps = workflowSteps
      }

stepFromJsonValue :: JValue -> ParseResult Step
stepFromJsonValue (JObject pairs) = do
  kind <- requiredText "kind" pairs
  stepName <- optionalText "name" pairs
  case kind of
    "exec" -> StepExec stepName <$> requiredText "command" pairs
    "echo" -> StepEcho stepName <$> requiredText "text" pairs
    "approve" -> do
      message <- fromMaybe "Approval required" <$> optionalText "message" pairs
      pure (StepApprove stepName (ApprovalGate message))
    _ -> Left (ParseError ("unsupported step kind: " <> kind))
stepFromJsonValue _ = Left (ParseError "each step must be an object")

requiredValue :: Text -> [(Text, JValue)] -> ParseResult JValue
requiredValue key pairs =
  case lookup key pairs of
    Nothing -> Left (ParseError ("missing required field: " <> key))
    Just value -> Right value

requiredText :: Text -> [(Text, JValue)] -> ParseResult Text
requiredText key pairs = do
  value <- requiredValue key pairs
  case value of
    JString t -> Right t
    _ -> Left (ParseError ("field " <> key <> " must be a string"))

optionalText :: Text -> [(Text, JValue)] -> ParseResult (Maybe Text)
optionalText key pairs =
  case lookup key pairs of
    Nothing -> Right Nothing
    Just (JString t) -> Right (Just t)
    Just _ -> Left (ParseError ("field " <> key <> " must be a string when present"))

optionalInt :: Text -> [(Text, JValue)] -> ParseResult (Maybe Int)
optionalInt key pairs =
  case lookup key pairs of
    Nothing -> Right Nothing
    Just (JNumber n) -> Right (Just n)
    Just _ -> Left (ParseError ("field " <> key <> " must be an integer when present"))

-- YAML parsing

parseYamlWorkflow :: Text -> ParseResult Workflow
parseYamlWorkflow content = do
  let numberedLines = zip [1 :: Int ..] (map T.stripEnd (T.lines content))
  (workflowName, workflowVersion, stepLines) <- parseYamlHeader numberedLines Nothing Nothing
  (workflowSteps, trailing) <- parseYamlSteps stepLines []

  unless (not (null workflowSteps)) (Left (ParseError "workflow.steps must contain at least one step"))
  unless (workflowVersion > 0) (Left (ParseError "workflow.version must be positive"))

  case dropIgnorable trailing of
    [] ->
      pure
        Workflow
          { workflowName = workflowName,
            workflowVersion = workflowVersion,
            workflowSteps = workflowSteps
          }
    (lineNo, lineText) : _ ->
      Left (ParseError ("unexpected content after steps at line " <> tshow lineNo <> ": " <> lineText))

parseYamlHeader :: [(Int, Text)] -> Maybe Text -> Maybe Int -> ParseResult (Text, Int, [(Int, Text)])
parseYamlHeader [] _ _ = Left (ParseError "missing `steps:` section")
parseYamlHeader ((lineNo, lineText) : rest) nameMaybe versionMaybe
  | isIgnorable lineText = parseYamlHeader rest nameMaybe versionMaybe
  | isIndented lineText =
      Left (ParseError ("top-level key must not be indented (line " <> tshow lineNo <> ")"))
  | lineText == "steps:" = do
      workflowName <- maybe (Left (ParseError "missing required field: name")) Right nameMaybe
      let workflowVersion = fromMaybe 1 versionMaybe
      pure (workflowName, workflowVersion, rest)
  | otherwise = do
      (key, value) <- parseKeyValue lineNo lineText
      case key of
        "name" -> parseYamlHeader rest (Just (parseScalar value)) versionMaybe
        "version" -> do
          version <- parsePositiveInt lineNo value
          parseYamlHeader rest nameMaybe (Just version)
        _ ->
          Left
            ( ParseError
                ( "unsupported top-level key at line "
                    <> tshow lineNo
                    <> ": "
                    <> key
                )
            )

parseYamlSteps :: [(Int, Text)] -> [Step] -> ParseResult ([Step], [(Int, Text)])
parseYamlSteps lines0 acc =
  case dropIgnorable lines0 of
    [] -> Right (reverse acc, [])
    lines1@((lineNo, lineText) : rest)
      | T.isPrefixOf "  - " lineText -> do
          (step, remaining) <- parseYamlStep lineNo lineText rest
          parseYamlSteps remaining (step : acc)
      | isIndented lineText ->
          Left
            ( ParseError
                ( "unexpected indentation in steps section at line "
                    <> tshow lineNo
                )
            )
      | null acc ->
          Left
            ( ParseError
                ( "steps section must contain at least one step; found line "
                    <> tshow lineNo
                )
            )
      | otherwise -> Right (reverse acc, lines1)

parseYamlStep :: Int -> Text -> [(Int, Text)] -> ParseResult (Step, [(Int, Text)])
parseYamlStep lineNo stepLine rest = do
  (firstKey, firstValue) <- parseKeyValue lineNo (T.drop 4 stepLine)
  if firstKey /= "kind"
    then
      Left
        ( ParseError
            ( "step at line "
                <> tshow lineNo
                <> " must begin with `kind:`"
            )
        )
    else do
      let kind = parseScalar firstValue
      (fieldPairs, remaining) <- gatherStepFields rest []
      let stepName = lookup "name" fieldPairs >>= nonEmptyMaybe . parseScalar

      step <-
        case kind of
          "exec" -> do
            command <- requiredField lineNo "command" fieldPairs
            pure (StepExec stepName (parseScalar command))
          "echo" -> do
            text <- requiredField lineNo "text" fieldPairs
            pure (StepEcho stepName (parseScalar text))
          "approve" -> do
            let message = maybe "Approval required" parseScalar (lookup "message" fieldPairs)
            pure (StepApprove stepName (ApprovalGate message))
          _ -> Left (ParseError ("unsupported step kind at line " <> tshow lineNo <> ": " <> kind))

      pure (step, remaining)

gatherStepFields :: [(Int, Text)] -> [(Text, Text)] -> ParseResult ([(Text, Text)], [(Int, Text)])
gatherStepFields lines0 acc =
  case dropIgnorable lines0 of
    [] -> Right (acc, [])
    allLines@((lineNo, lineText) : rest)
      | T.isPrefixOf "    " lineText -> do
          (key, value) <- parseKeyValue lineNo (T.drop 4 lineText)
          gatherStepFields rest ((key, value) : acc)
      | T.isPrefixOf "  - " lineText -> Right (acc, allLines)
      | isIndented lineText ->
          Left
            ( ParseError
                ( "invalid step field indentation at line "
                    <> tshow lineNo
                )
            )
      | otherwise -> Right (acc, allLines)

requiredField :: Int -> Text -> [(Text, Text)] -> ParseResult Text
requiredField lineNo key pairs =
  case lookup key pairs of
    Nothing ->
      Left
        ( ParseError
            ( "missing `"
                <> key
                <> "` for step at line "
                <> tshow lineNo
            )
        )
    Just value -> Right value

parseKeyValue :: Int -> Text -> ParseResult (Text, Text)
parseKeyValue lineNo lineText =
  case T.breakOn ":" lineText of
    (rawKey, rawRest)
      | T.null rawRest ->
          Left
            ( ParseError
                ( "expected key:value pair at line "
                    <> tshow lineNo
                )
            )
      | otherwise ->
          let key = T.strip rawKey
              value = T.strip (T.drop 1 rawRest)
           in if T.null key
                then Left (ParseError ("empty key at line " <> tshow lineNo))
                else Right (key, value)

parsePositiveInt :: Int -> Text -> ParseResult Int
parsePositiveInt lineNo raw =
  case reads (T.unpack (T.strip raw)) of
    [(value, "")] | value > 0 -> Right value
    _ -> Left (ParseError ("invalid positive integer at line " <> tshow lineNo))

parseScalar :: Text -> Text
parseScalar raw
  | T.length trimmed >= 2 && T.head trimmed == '"' && T.last trimmed == '"' = T.init (T.tail trimmed)
  | T.length trimmed >= 2 && T.head trimmed == '\'' && T.last trimmed == '\'' = T.init (T.tail trimmed)
  | otherwise = trimmed
  where
    trimmed = T.strip raw

nonEmptyMaybe :: Text -> Maybe Text
nonEmptyMaybe t
  | T.null t = Nothing
  | otherwise = Just t

isIndented :: Text -> Bool
isIndented lineText =
  case T.uncons lineText of
    Just (' ', _) -> True
    _ -> False

isIgnorable :: Text -> Bool
isIgnorable lineText =
  let stripped = T.strip lineText
   in T.null stripped || T.isPrefixOf "#" stripped

dropIgnorable :: [(Int, Text)] -> [(Int, Text)]
dropIgnorable = dropWhile (isIgnorable . snd)

tshow :: Show a => a -> Text
tshow = T.pack . show
