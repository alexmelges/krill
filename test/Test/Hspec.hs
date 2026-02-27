{-# LANGUAGE ScopedTypeVariables #-}

module Test.Hspec
  ( Spec,
    expectationFailure,
    hspec,
    it,
    shouldBe,
    shouldContain,
    shouldSatisfy,
  )
where

import Control.Exception (SomeException, catch, throwIO)
import Control.Monad (unless)
import Data.Text (Text)
import qualified Data.Text as T

type Spec = IO ()

hspec :: Spec -> IO ()
hspec = id

it :: String -> IO () -> Spec
it label action =
  action `catch` \(err :: SomeException) -> do
    putStrLn ("[FAIL] " <> label)
    throwIO err

expectationFailure :: String -> IO a
expectationFailure message = throwIO (userError message)

shouldBe :: (Eq a, Show a) => a -> a -> IO ()
shouldBe actual expected =
  unless (actual == expected) $ expectationFailure ("Expected: " <> show expected <> ", got: " <> show actual)

shouldSatisfy :: Show a => a -> (a -> Bool) -> IO ()
shouldSatisfy actual predicate =
  unless (predicate actual) $ expectationFailure ("Value did not satisfy predicate: " <> show actual)

shouldContain :: Text -> Text -> IO ()
shouldContain actual expected =
  unless (expected `T.isInfixOf` actual) $ expectationFailure ("Expected substring " <> show expected <> " in " <> show actual)
