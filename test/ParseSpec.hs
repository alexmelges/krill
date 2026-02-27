{-# LANGUAGE OverloadedStrings #-}

module ParseSpec (spec) where

import qualified Data.ByteString.Char8 as BS8
import Krill.Parse (parseWorkflowBytes)
import Krill.Types (ApprovalGate (..), Step (..), Workflow (..))
import Test.Hspec (Spec, expectationFailure, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = do
  it "parses YAML workflows" $ do
    let raw =
          BS8.unlines
            [ "name: yaml-flow",
              "version: 1",
              "steps:",
              "  - kind: echo",
              "    text: hello",
              "  - kind: approve",
              "    message: continue?"
            ]

    case parseWorkflowBytes raw of
      Left err -> expectationFailure ("unexpected parse error: " <> show err)
      Right workflow -> do
        workflowName workflow `shouldBe` "yaml-flow"
        workflowVersion workflow `shouldBe` 1
        workflowSteps workflow
          `shouldBe` [ StepEcho {stepName = Nothing, stepText = "hello"},
                       StepApprove {stepName = Nothing, stepGate = ApprovalGate {approvalMessage = "continue?"}}
                     ]

  it "parses JSON workflows" $ do
    let raw =
          BS8.unlines
            [ "{",
              "  \"name\": \"json-flow\",",
              "  \"version\": 1,",
              "  \"steps\": [",
              "    {\"kind\": \"exec\", \"command\": \"echo hi\"}",
              "  ]",
              "}"
            ]

    case parseWorkflowBytes raw of
      Left err -> expectationFailure ("unexpected parse error: " <> show err)
      Right workflow ->
        workflowSteps workflow
          `shouldBe` [StepExec {stepName = Nothing, stepCommand = "echo hi"}]

  it "rejects unsupported step kinds" $ do
    let raw =
          BS8.unlines
            [ "name: bad-flow",
              "version: 1",
              "steps:",
              "  - kind: unknown"
            ]

    parseWorkflowBytes raw `shouldSatisfy` isLeft

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft (Right _) = False
