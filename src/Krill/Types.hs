module Krill.Types
  ( ApprovalGate (..),
    RunLog (..),
    RunState (..),
    RunStatus (..),
    Step (..),
    Workflow (..),
  )
where

import Data.Text (Text)
import Data.Time (UTCTime)

data Workflow = Workflow
  { workflowName :: Text,
    workflowVersion :: Int,
    workflowSteps :: [Step]
  }
  deriving (Eq, Show)

data Step
  = StepExec
      { stepName :: Maybe Text,
        stepCommand :: Text
      }
  | StepEcho
      { stepName :: Maybe Text,
        stepText :: Text
      }
  | StepApprove
      { stepName :: Maybe Text,
        stepGate :: ApprovalGate
      }
  deriving (Eq, Show)

data ApprovalGate = ApprovalGate
  { approvalMessage :: Text
  }
  deriving (Eq, Show)

data RunStatus
  = RunPending
  | RunRunning
  | RunSucceeded
  | RunFailed
  deriving (Eq, Show)

data RunState = RunState
  { runId :: Text,
    runWorkflowName :: Text,
    runStatus :: RunStatus,
    runCurrentStep :: Int,
    runStartedAt :: UTCTime,
    runFinishedAt :: Maybe UTCTime
  }
  deriving (Eq, Show)

data RunLog = RunLog
  { runLogTimestamp :: UTCTime,
    runLogRunId :: Text,
    runLogWorkflow :: Text,
    runLogStepIndex :: Maybe Int,
    runLogStepName :: Maybe Text,
    runLogEvent :: Text,
    runLogMessage :: Text,
    runLogStatus :: Maybe RunStatus
  }
  deriving (Eq, Show)
