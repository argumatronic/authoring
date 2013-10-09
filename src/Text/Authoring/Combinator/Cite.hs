{-# LANGUAGE OverloadedStrings #-}

module Text.Authoring.Combinator.Cite where

import Control.Lens
import Control.Monad
import Control.Monad.State
import Control.Monad.Writer
import qualified Data.Set as Set
import qualified Data.Text as Text
import Text.CSL.Input.Identifier (resolve, HasDatabase)


import Text.Authoring.Combinator.Meta
import Text.Authoring.Combinator.Writer
import Text.Authoring.Document
import Text.Authoring.State


citet, citep :: (MonadState s m, HasAuthorState s, HasDatabase s, 
          MonadWriter w m, HasDocument w, MonadIO m) => [String] -> m ()

citet = citationGen "citet"
citep = citationGen "citep"

citet1, citep1 :: (MonadState s m, HasAuthorState s, HasDatabase s, 
          MonadWriter w m, HasDocument w, MonadIO m) => String -> m ()

citet1 = citationGen "citet" . (:[]) -- + ---<===   I am a long man lying
citep1 = citationGen "citep" . (:[]) -- + ---<===   We are long men lying

-- | make a citation to a document(s).
citationGen :: (MonadState s m, HasAuthorState s, HasDatabase s, 
          MonadWriter w m, HasDocument w, MonadIO m) => Text.Text -> [String] -> m ()
citationGen cmdName  urls = do
  mapM_ resolve urls
  command1 cmdName $ braces $ raw $ Text.intercalate "," $ map Text.pack urls
