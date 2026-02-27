{-# LANGUAGE OverloadedStrings #-}

module RunSpec (spec) where

import Control.Exception (finally)
import qualified Data.ByteString.Char8 as BS8
import Data.Time (defaultTimeLocale, formatTime, getCurrentTime)
import Krill.Run
  ( RunConfig (..),
    RunFailure (..),
    RunOutcome (..),
    runWorkflow,
  )
import Krill.Types
  ( ApprovalGate (..),
    RunState (..),
    RunStatus (..),
    Step (..),
    Workflow (..),
  )
import System.Directory (createDirectoryIfMissing, doesFileExist, getTemporaryDirectory, removePathForcibly)
import System.FilePath ((</>))
import Test.Hspec (Spec, expectationFailure, it, shouldBe, shouldContain, shouldSatisfy)

spec :: Spec
spec = do
  it "runs an echo workflow successfully and writes a log" $
    withTempDirectory "krill-run-success" $ \tmpDir -> do
      let workflow =
            Workflow
              { workflowName = "echo-only",
                workflowVersion = 1,
                workflowSteps = [StepEcho {stepName = Nothing, stepText = "hello"}]
              }
          config =
            RunConfig
              { runAutoApprove = False,
                runInteractiveApproval = False,
                runLogRoot = tmpDir
              }

      result <- runWorkflow config workflow
      case result of
        Left failure -> expectationFailure ("expected success, got failure: " <> show failure)
        Right outcome -> do
          runStatus (runOutcomeState outcome) `shouldBe` RunSucceeded
          logExists <- doesFileExist (runOutcomeLogPath outcome)
          logExists `shouldBe` True
          logContent <- BS8.readFile (runOutcomeLogPath outcome)
          logContent `shouldSatisfy` (not . BS8.null)

  it "fails approve step in non-interactive mode without --auto-approve" $
    withTempDirectory "krill-run-approval-fail" $ \tmpDir -> do
      let workflow =
            Workflow
              { workflowName = "needs-approval",
                workflowVersion = 1,
                workflowSteps = [StepApprove {stepName = Nothing, stepGate = ApprovalGate "Need approval"}]
              }
          config =
            RunConfig
              { runAutoApprove = False,
                runInteractiveApproval = False,
                runLogRoot = tmpDir
              }

      result <- runWorkflow config workflow
      case result of
        Right outcome -> expectationFailure ("expected failure, got success: " <> show outcome)
        Left failure -> do
          runStatus (runFailureState failure) `shouldBe` RunFailed
          runFailureMessage failure `shouldContain` "--auto-approve"
          logExists <- doesFileExist (runFailureLogPath failure)
          logExists `shouldBe` True

  it "passes approve step when --auto-approve is enabled" $
    withTempDirectory "krill-run-approval-pass" $ \tmpDir -> do
      let workflow =
            Workflow
              { workflowName = "auto-approved",
                workflowVersion = 1,
                workflowSteps = [StepApprove {stepName = Nothing, stepGate = ApprovalGate "Need approval"}]
              }
          config =
            RunConfig
              { runAutoApprove = True,
                runInteractiveApproval = False,
                runLogRoot = tmpDir
              }

      result <- runWorkflow config workflow
      case result of
        Left failure -> expectationFailure ("expected success, got failure: " <> show failure)
        Right outcome -> runStatus (runOutcomeState outcome) `shouldBe` RunSucceeded

withTempDirectory :: String -> (FilePath -> IO a) -> IO a
withTempDirectory label action = do
  tempRoot <- getTemporaryDirectory
  now <- getCurrentTime
  let suffix = formatTime defaultTimeLocale "%Y%m%dT%H%M%S%q" now
      dir = tempRoot </> (label <> "-" <> suffix)
  createDirectoryIfMissing True dir
  action dir `finally` removePathForcibly dir
