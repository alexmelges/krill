module Main (main) where

import qualified ParseSpec
import qualified RunSpec
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
  ParseSpec.spec
  RunSpec.spec
