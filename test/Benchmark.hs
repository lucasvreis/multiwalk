{-# LANGUAGE RankNTypes #-}

module Main where

import Commonmark.Pandoc
import Commonmark.Parser
import Control.DeepSeq
import Control.Exception (evaluate)
import qualified Control.Monad.Trans.Writer.Lazy as LW
import qualified Control.Monad.Trans.Writer.Strict as CPSW
import qualified Control.Monad.Trans.Writer.Strict as SW
import Control.MultiWalk
import qualified Data.ByteString as B
import Data.Functor (($>))
import Data.Functor.Compose (Compose (..))
import Data.List (sort)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8)
import Test.Tasty.Bench
import Test.Tasty.HUnit
import Text.Pandoc.Builder (Blocks, toList)
import Text.Pandoc.Definition
import Text.Pandoc.Generic (queryWith)
import qualified Text.Pandoc.Walk as PW

data PTag

instance MultiTag PTag where
  type
    MultiTypes PTag =
      '[ Block
       , Inline
       ]

type DoubleList a = MatchWith [[a]] (Trav (Compose [] []) a)

instance MultiSub PTag Block where
  type
    SubTypes PTag Block =
      'SpecList
        '[ ToSpec (Trav [] Inline)
         , ToSpec (DoubleList Inline)
         , ToSpec (Trav [] Block)
         , ToSpec (DoubleList Block)
         , ToSpec
            ( Under
                [([Inline], [[Block]])]
                'NoSel
                (Under ([Inline], [[Block]]) 'NoSel (Trav [] Inline))
            )
         , ToSpec
            ( Under
                [([Inline], [[Block]])]
                'NoSel
                (Under ([Inline], [[Block]]) 'NoSel (DoubleList Block))
            )
         ]

instance MultiSub PTag Inline where
  type
    SubTypes PTag Inline =
      'SpecList '[ToSpec (Trav [] Inline), ToSpec (Trav [] Block)]

prepEnv :: IO [Block]
prepEnv = do
  text <- decodeUtf8 <$> B.readFile "test/text.md"
  Right (Cm b :: Cm () Blocks) <- pure $ commonmark "test/text.md" text
  evaluate $ force $ toList b

multiLW :: [Block] -> [Text]
multiLW = foldMap (LW.execWriter . w)
  where
    w = buildMultiW @PTag $ \f list ->
      let blks x@(CodeBlock _ c) = LW.tell [c] $> x
          blks x = f x
          inls x@(Code _ c) = LW.tell [c] $> x
          inls x = f x
       in list .> blks .> inls

multiSW :: [Block] -> [Text]
multiSW = foldMap (SW.execWriter . w)
  where
    w = buildMultiW @PTag $ \f list ->
      let blks x@(CodeBlock _ c) = SW.tell [c] $> x
          blks x = f x
          inls x@(Code _ c) = SW.tell [c] $> x
          inls x = f x
       in list .> blks .> inls

multiCPSW :: [Block] -> [Text]
multiCPSW = foldMap (CPSW.execWriter . w)
  where
    w = buildMultiW @PTag $ \f list ->
      let blks x@(CodeBlock _ c) = CPSW.tell [c] $> x
          blks x = f x
          inls x@(Code _ c) = CPSW.tell [c] $> x
          inls x = f x
       in list .> blks .> inls

multi :: [Block] -> [Text]
multi = foldMap $
  buildMultiQ @PTag $ \sub list ->
    list ?> blks sub ?> inls sub
  where
    blks :: Query PTag [Text] -> Block -> [Text]
    blks _ (CodeBlock _ c) = [c]
    blks f x = f x
    inls :: Query PTag [Text] -> Inline -> [Text]
    inls _ (Code _ c) = [c]
    inls f x = f x

gene :: [Block] -> [Text]
gene x = queryWith blks x <> queryWith inls x
  where
    blks :: Block -> [Text]
    blks (CodeBlock _ c) = [c]
    blks _ = []
    inls :: Inline -> [Text]
    inls (Code _ c) = [c]
    inls _ = []

wal :: [Block] -> [Text]
wal x = PW.query blks x <> PW.query inls x
  where
    blks :: Block -> [Text]
    blks (CodeBlock _ c) = [c]
    blks _ = []
    inls :: Inline -> [Text]
    inls (Code _ c) = [c]
    inls _ = []

main :: IO ()
main =
  defaultMain
    [ bgroup
        "query"
        [ env prepEnv $ bench "multiwalk" . nf multi
        , env prepEnv $ bench "mw lw" . nf multiLW
        , env prepEnv $ bench "mw sw" . nf multiSW
        , env prepEnv $ bench "mw cpsw" . nf multiCPSW
        , env prepEnv $ bench "syb" . nf gene
        , env prepEnv $ bench "pandoc.walk" . nf wal
        , env prepEnv $ \blocks ->
            -- The other implementations return out of order (!!!) fragments, but sorted they should be the same.
            bgroup
              "equality"
              [ testCase "multiwalk eq syb" (sort (multi blocks) @?= sort (gene blocks))
              , testCase "multiwalk eq pandoc.walk" (sort (multi blocks) @?= sort (wal blocks))
              ]
        ]
    ]
