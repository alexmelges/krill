{-# LANGUAGE OverloadedStrings #-}

module Krill.Run
  ( RunConfig (..),
    RunFailure (..),
    RunOutcome (..),
    defaultRunConfig,
    runWorkflow,
  )
where

import Control.Exception (Exception, SomeException, catch, try)
import Control.Monad (filterM, unless)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (UTCTime, defaultTimeLocale, formatTime, getCurrentTime)
import Krill.Types
  ( ApprovalGate (approvalMessage),
    HttpStep (..),
    RunLog (..),
    RunState (..),
    RunStatus (..),
    Step (..),
    Workflow (..),
  )
import qualified Data.ByteString.Lazy as BSL
import qualified Data.Text.Encoding as TE
import Network.HTTP.Client
import Network.HTTP.Types.Status (statusCode)
import System.Environment (getEnv, lookupEnv)
import System.Directory (createDirectoryIfMissing)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (Handle, IOMode (WriteMode), hFlush, hIsTerminalDevice, hPutStr, stderr, stdin, stdout, withFile)
import System.Process (readCreateProcessWithExitCode, shell)

-- Variable interpolation: ${VAR_NAME} from environment
interpolateVars :: Text -> IO Text
interpolateVars text = go text
  where
    go t = case T.breakOn "${" t of
      (before, after) 
        | T.null after -> pure before
        | otherwise -> case T.breakOn "}" (T.drop 2 after) of
          (varName, rest') 
            | T.null rest' -> pure (before <> after)  -- unmatched ${
            | otherwise -> do
              val <- lookupEnv (T.unpack varName)
              let replacement = maybe "" T.pack val
              interpolated <- go (T.drop 1 rest')  -- skip the closing }
              pure (before <> replacement <> interpolated)

-- Apply variable interpolation to step text fields
interpolateStep :: Step -> IO Step
interpolateStep step@StepEcho{} = do
  newText <- interpolateVars (stepText step)
  pure step { stepText = newText }
interpolateStep step@StepExec{} = do
  newCommand <- interpolateVars (stepCommand step)
  pure step { stepCommand = newCommand }
interpolateStep step@StepHttp{} = do
  newUrl <- interpolateVars (httpUrl (stepHttp step))
  newBody <- case httpBody (stepHttp step) of
    Nothing -> pure Nothing
    Just b -> Just <$> interpolateVars b
  pure step { stepHttp = (stepHttp step) { httpUrl = newUrl, httpBody = newBody } }
interpolateStep step = pure step

data RunConfig = RunConfig
  { runAutoApprove :: Bool,
    runInteractiveApproval :: Bool,
    runLogRoot :: FilePath
  }
  deriving (Eq, Show)

data RunFailure = RunFailure
  { runFailureState :: RunState,
    runFailureLogPath :: FilePath,
    runFailureStepIndex :: Maybe Int,
    runFailureMessage :: Text
  }
  deriving (Eq, Show)

data RunOutcome = RunOutcome
  { runOutcomeState :: RunState,
    runOutcomeLogPath :: FilePath
  }
  deriving (Eq, Show)

defaultRunConfig :: Bool -> IO RunConfig
defaultRunConfig autoApprove = do
  interactive <- hIsTerminalDevice stdin
  pure
    RunConfig
      { runAutoApprove = autoApprove,
        runInteractiveApproval = interactive,
        runLogRoot = ".krill/runs"
      }

runWorkflow :: RunConfig -> Workflow -> IO (Either RunFailure RunOutcome)
runWorkflow config workflow = do
  startedAt <- getCurrentTime
  let runIdText = T.pack (formatTime defaultTimeLocale "%Y%m%dT%H%M%S%qZ" startedAt)
      logPath = runLogRoot config </> T.unpack runIdText <> ".jsonl"
      runningState =
        RunState
          { runId = runIdText,
            runWorkflowName = workflowName workflow,
            runStatus = RunRunning,
            runCurrentStep = 0,
            runStartedAt = startedAt,
            runFinishedAt = Nothing
          }

  createDirectoryIfMissing True (runLogRoot config)

  withFile logPath WriteMode $ \handle -> do
    logEvent handle workflow runningState Nothing Nothing "run_started" "Workflow execution started" (Just RunRunning)
    runResult <- runSteps config handle workflow runningState 1 (workflowSteps workflow)

    finishedAt <- getCurrentTime
    case runResult of
      Left (stepIndex, message, failedState) -> do
        let terminalState = failedState {runStatus = RunFailed, runFinishedAt = Just finishedAt}
        logEvent handle workflow terminalState (Just stepIndex) Nothing "run_failed" message (Just RunFailed)
        pure
          ( Left
              RunFailure
                { runFailureState = terminalState,
                  runFailureLogPath = logPath,
                  runFailureStepIndex = Just stepIndex,
                  runFailureMessage = message
                }
          )
      Right successState -> do
        let terminalState = successState {runStatus = RunSucceeded, runFinishedAt = Just finishedAt}
        logEvent handle workflow terminalState Nothing Nothing "run_completed" "Workflow execution completed" (Just RunSucceeded)
        pure
          ( Right
              RunOutcome
                { runOutcomeState = terminalState,
                  runOutcomeLogPath = logPath
                }
          )

runSteps :: RunConfig -> Handle -> Workflow -> RunState -> Int -> [Step] -> IO (Either (Int, Text, RunState) RunState)
runSteps _ _ _ state _ [] = pure (Right state)
runSteps config handle workflow state stepIndex (step : rest) = do
  let stepState = state {runCurrentStep = stepIndex}
      stepNameText = stepDisplayName step
      currentStepName = stepNameOf step

  -- Apply variable interpolation before execution
  step' <- interpolateStep step

  logEvent handle workflow stepState (Just stepIndex) currentStepName "step_started" ("Starting step: " <> stepNameText) Nothing

  execution <- executeStep config step'
  case execution of
    Left err -> do
      logEvent handle workflow stepState (Just stepIndex) currentStepName "step_failed" err (Just RunFailed)
      pure (Left (stepIndex, err, stepState))
    Right msg -> do
      logEvent handle workflow stepState (Just stepIndex) currentStepName "step_completed" msg Nothing
      runSteps config handle workflow stepState (stepIndex + 1) rest

executeStep :: RunConfig -> Step -> IO (Either Text Text)
executeStep _ StepEcho {stepText} = do
  TIO.putStrLn stepText
  pure (Right "echo output emitted")
executeStep _ StepExec {stepCommand} = do
  (exitCode, commandStdout, commandStderr) <- readCreateProcessWithExitCode (shell (T.unpack stepCommand)) ""
  unless (null commandStdout) (putStr commandStdout)
  unless (null commandStderr) (hPutStr stderr commandStderr)
  case exitCode of
    ExitSuccess -> pure (Right "exec command completed")
    ExitFailure code -> pure (Left ("exec command failed with exit code " <> T.pack (show code)))
executeStep config StepApprove {stepGate} = evaluateApproval config stepGate
executeStep _ StepHttp {stepHttp} = executeHttpStep stepHttp
executeStep _ StepEnv {stepEnvRequired} = validateEnv stepEnvRequired

evaluateApproval :: RunConfig -> ApprovalGate -> IO (Either Text Text)
evaluateApproval config gate
  | runAutoApprove config = pure (Right "approval granted by --auto-approve")
  | runInteractiveApproval config = do
      TIO.putStr (approvalMessage gate <> " [y/N]: ")
      hFlush stdout
      response <- TIO.getLine
      if normalizeApproval response
        then pure (Right "approval granted interactively")
        else pure (Left "approval denied by user")
  | otherwise = pure (Left "approval required but no TTY detected; rerun with --auto-approve")

normalizeApproval :: Text -> Bool
normalizeApproval response =
  case T.toLower (T.strip response) of
    "y" -> True
    "yes" -> True
    _ -> False

stepDisplayName :: Step -> Text
stepDisplayName StepExec {stepName} = maybe "exec" id stepName
stepDisplayName StepEcho {stepName} = maybe "echo" id stepName
stepDisplayName StepApprove {stepName} = maybe "approve" id stepName
stepDisplayName StepHttp {stepName} = maybe "http" id stepName
stepDisplayName StepEnv {stepName} = maybe "env" id stepName

stepNameOf :: Step -> Maybe Text
stepNameOf StepExec {stepName} = stepName
stepNameOf StepEcho {stepName} = stepName
stepNameOf StepApprove {stepName} = stepName
stepNameOf StepHttp {stepName} = stepName
stepNameOf StepEnv {stepName} = stepName

validateEnv :: [Text] -> IO (Either Text Text)
validateEnv [] = pure (Right "no environment variables required")
validateEnv required = do
  missing <- filterM (fmap not . isPresent) required
  if null missing
    then pure (Right ("validated environment variables: " <> T.intercalate ", " required))
    else pure (Left ("missing required environment variables: " <> T.intercalate ", " missing))
  where
    isPresent var = do
      result <- lookupEnv (T.unpack var)
      pure (case result of
        Nothing -> False
        Just "" -> False
        _ -> True)

executeHttpStep :: HttpStep -> IO (Either Text Text)
executeHttpStep httpStep = do
  let urlText = httpUrl httpStep
      methodText = httpMethod httpStep
      mBody = httpBody httpStep
  
  case parseUrl (T.unpack urlText) of
    Left err -> pure (Left ("invalid URL: " <> urlText <> " - " <> T.pack (show err)))
    Right req -> do
      let req' = req
            { method = TE.encodeUtf8 methodText
            }
          req'' = case mBody of
            Nothing -> req'
            Just body -> req' { requestBody = RequestBodyLBS (BSL.fromStrict (TE.encodeUtf8 body)) }
      
      manager <- newManager defaultManagerSettings
      result <- tryHttp manager req''
      case result of
        Left err -> pure (Left ("HTTP request failed: " <> T.pack (show err)))
        Right resp -> pure (Right ("HTTP " <> methodText <> " " <> urlText <> " -> " <> T.pack (show (statusCode (responseStatus resp)))))

tryHttp :: Manager -> Request -> IO (Either HttpException (Response BSL.ByteString))
tryHttp manager req = try (httpLbs req manager)

logEvent :: Handle -> Workflow -> RunState -> Maybe Int -> Maybe Text -> Text -> Text -> Maybe RunStatus -> IO ()
logEvent handle workflow state stepIndex stepName eventName message statusOverride = do
  eventTime <- getCurrentTime
  let entry =
        RunLog
          { runLogTimestamp = eventTime,
            runLogRunId = runId state,
            runLogWorkflow = workflowName workflow,
            runLogStepIndex = stepIndex,
            runLogStepName = stepName,
            runLogEvent = eventName,
            runLogMessage = message,
            runLogStatus = statusOverride
          }
  TIO.hPutStrLn handle (renderRunLog entry)

renderRunLog :: RunLog -> Text
renderRunLog entry =
  renderObject
    [ ("timestamp", renderString (formatUtc (runLogTimestamp entry))),
      ("runId", renderString (runLogRunId entry)),
      ("workflow", renderString (runLogWorkflow entry)),
      ("stepIndex", renderMaybe renderInt (runLogStepIndex entry)),
      ("stepName", renderMaybe renderString (runLogStepName entry)),
      ("event", renderString (runLogEvent entry)),
      ("message", renderString (runLogMessage entry)),
      ("status", renderMaybe (renderString . renderStatus) (runLogStatus entry))
    ]

renderObject :: [(Text, Text)] -> Text
renderObject fields =
  "{" <> T.intercalate "," (map renderField fields) <> "}"

renderField :: (Text, Text) -> Text
renderField (key, value) = renderString key <> ":" <> value

renderMaybe :: (a -> Text) -> Maybe a -> Text
renderMaybe _ Nothing = "null"
renderMaybe renderFn (Just value) = renderFn value

renderInt :: Int -> Text
renderInt = T.pack . show

renderStatus :: RunStatus -> Text
renderStatus status =
  case status of
    RunPending -> "pending"
    RunRunning -> "running"
    RunSucceeded -> "succeeded"
    RunFailed -> "failed"

renderString :: Text -> Text
renderString textValue = "\"" <> escapeJson textValue <> "\""

escapeJson :: Text -> Text
escapeJson = T.concatMap escapeChar

escapeChar :: Char -> Text
escapeChar c =
  case c of
    '"' -> "\\\""
    '\\' -> "\\\\"
    '\n' -> "\\n"
    '\r' -> "\\r"
    '\t' -> "\\t"
    _ -> T.singleton c

formatUtc :: UTCTime -> Text
formatUtc = T.pack . formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ"
