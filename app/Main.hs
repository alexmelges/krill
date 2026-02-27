{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Krill.Parse (ParseError (..), parseWorkflowFile)
import Krill.Run (RunFailure (..), RunOutcome (..), defaultRunConfig, runWorkflow)
import Krill.Types (RunState (runStatus), RunStatus (RunSucceeded))
import System.Environment (getArgs)
import System.Exit (exitFailure, exitSuccess)
import System.IO (stderr)

data Command
  = RunCommand RunOptions
  | ValidateCommand FilePath

data RunOptions = RunOptions
  { runFile :: FilePath,
    runAutoApproveFlag :: Bool
  }

main :: IO ()
main = do
  args <- getArgs
  case parseArgs args of
    Left err -> do
      TIO.hPutStrLn stderr err
      TIO.hPutStrLn stderr usageText
      exitFailure
    Right command -> runCommand command

parseArgs :: [String] -> Either Text Command
parseArgs ("run" : rest) = RunCommand <$> parseRunOptions rest (RunOptions "" False)
parseArgs ("validate" : rest) = ValidateCommand <$> parseValidateOptions rest
parseArgs _ = Left "Expected subcommand: run | validate"

parseRunOptions :: [String] -> RunOptions -> Either Text RunOptions
parseRunOptions [] options
  | null (runFile options) = Left "Missing required option: --file <PATH>"
  | otherwise = Right options
parseRunOptions ("--file" : path : rest) options =
  parseRunOptions rest options {runFile = path}
parseRunOptions ("-f" : path : rest) options =
  parseRunOptions rest options {runFile = path}
parseRunOptions ("--auto-approve" : rest) options =
  parseRunOptions rest options {runAutoApproveFlag = True}
parseRunOptions (arg : _) _ = Left ("Unknown run option: " <> tshow arg)

parseValidateOptions :: [String] -> Either Text FilePath
parseValidateOptions ["--file", path] = Right path
parseValidateOptions ["-f", path] = Right path
parseValidateOptions [] = Left "Missing required option: --file <PATH>"
parseValidateOptions (arg : _) = Left ("Unknown validate option: " <> tshow arg)

runCommand :: Command -> IO ()
runCommand (ValidateCommand workflowPath) = do
  parsed <- parseWorkflowFile workflowPath
  case parsed of
    Left parseError -> reportParseError parseError
    Right _ -> do
      putStrLn "Workflow is valid."
      exitSuccess
runCommand (RunCommand options) = do
  parsed <- parseWorkflowFile (runFile options)
  case parsed of
    Left parseError -> reportParseError parseError
    Right workflow -> do
      config <- defaultRunConfig (runAutoApproveFlag options)
      runResult <- runWorkflow config workflow
      case runResult of
        Left failure -> do
          TIO.hPutStrLn stderr ("Run failed: " <> runFailureMessage failure)
          putStrLn ("Run log: " <> runFailureLogPath failure)
          exitFailure
        Right outcome -> do
          putStrLn "Run completed successfully."
          putStrLn ("Run log: " <> runOutcomeLogPath outcome)
          if runStatus (runOutcomeState outcome) == RunSucceeded
            then exitSuccess
            else exitFailure

reportParseError :: ParseError -> IO a
reportParseError parseError = do
  TIO.hPutStrLn stderr ("Validation failed: " <> parseErrorMessage parseError)
  exitFailure

usageText :: Text
usageText =
  T.unlines
    [ "Usage:",
      "  krill validate --file <PATH>",
      "  krill run --file <PATH> [--auto-approve]"
    ]

tshow :: Show a => a -> Text
tshow = T.pack . show
