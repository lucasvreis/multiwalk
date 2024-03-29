module Main (main) where

import Control.MultiWalk
import Data.Functor.Compose (Compose (..))
import Data.Functor.Identity (Identity (..))
import GHC.Generics (Generic)
import Test.Tasty
import Test.Tasty.HUnit

data Foo
  = Foo1 String
  | Foo2 String Foo
  | Foo3 [Int] String [[Int]] Int [Int]
  deriving (Eq, Show, Generic)

data FooTag

instance MultiTag FooTag where
  type
    MultiTypes FooTag =
      '[ String
       , Foo
       , Int
       , [Int]
       ]

instance MultiSub FooTag Foo where
  type
    SubTypes FooTag Foo =
      'SpecList
        '[ ToSpec Foo
         , ToSpec String
         , ToSpec (MatchWith [[Int]] (Trav (Compose [] []) Int))
         , ToSpec [Int]
         ]

instance MultiSub FooTag String where
  type SubTypes FooTag String = 'SpecLeaf

instance MultiSub FooTag Int where
  type SubTypes FooTag Int = 'SpecLeaf

instance MultiSub FooTag [Int] where
  type SubTypes FooTag [Int] = 'SpecList '[ToSpec (Trav [] Int)]

sampleFoo :: Foo
sampleFoo = Foo2 "bla" (Foo2 "blblo" (Foo1 "ok"))

list' :: FList Identity '[String, Foo, Int, [Int]]
list' = (Identity . ('2' :)) :.: pure :.: (Identity . (2 *)) :.: (\x -> Identity (x ++ x)) :.: FNil

sampleFoo2 :: Foo
sampleFoo2 = Foo3 [0, 1] "abc" [[4, 8, 9], [5, 6, 7]] 32 [2, 3]

tests :: TestTree
tests =
  testGroup
    "Tests"
    [ testGroup
        "Query"
        [ testCase "Foo" $
            query @FooTag (\(x :: Foo) -> [x]) sampleFoo
              @?= [Foo2 "bla" (Foo2 "blblo" (Foo1 "ok")), Foo2 "blblo" (Foo1 "ok"), Foo1 "ok"]
        , testCase "String" $
            query @FooTag (\(x :: String) -> [x]) sampleFoo
              @?= ["bla", "blblo", "ok"]
        ]
    , testCase "ModSub" $
        walkSub @FooTag list' sampleFoo2
          @?= Identity (Foo3 [0, 1, 0, 1] "2abc" [[8, 16, 18], [10, 12, 14]] 32 [2, 3, 2, 3])
    ]

main :: IO ()
main = defaultMain tests
