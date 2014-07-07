{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

{-|

This module provides quasi-quotes 'rawQ' and 'escQ' for writing papers. 
The quasi-quotes will generate authoring monads, so you can use them in authoring 
context like follows.

> paragraph = do
>   let takahashi2007 = citep ["isbn:9784130627184"] 
>       val = 3e6
>   [rawQ| The dielectric strength of air is $ #{val} $ V/m @{takahashi2007}.  |]

We support antiquote syntax:

>  #{val}

for embedding values ('Show' instance is required), and

>  @{...}

for embedding authring monads.

-}

module Text.Authoring.TH (rawQ, escQ, inputQ, declareLabels) where


import Control.Applicative
import Control.Monad
import Data.Char (isSpace, toUpper, toLower)
import Data.Typeable (Typeable)
import Data.Monoid
import qualified Data.Text as T
import qualified Language.Haskell.Meta.Parse.Careful as Meta
import Language.Haskell.TH
import Language.Haskell.TH.Quote
import Text.Trifecta
import Text.Trifecta.Delta
import Text.Parser.LookAhead
import Text.PrettyPrint.ANSI.Leijen as Pretty hiding (line, (<>), (<$>), empty, string)
import Text.Printf
import Safe (readMay)
import System.IO

import Text.Authoring.Combinator.Writer (raw, esc)
import Text.Authoring.Label (Label, fromValue)


-- | Quote with LaTeX special characters escaped. 
escQ = rawQ {quoteExp =  parseE (QQConfig { escaper = appE (varE 'esc)})}


-- | Quote without escaping any special characters.                                                           
rawQ :: QuasiQuoter
rawQ = QuasiQuoter { 
  quoteExp = parseE (QQConfig { escaper = appE (varE 'raw)}),
  quotePat  = error "Authoring QuasiQuotes are only for expression context" ,  
  quoteType = error "Authoring QuasiQuotes are only for expression context" ,  
  quoteDec  = error "Authoring QuasiQuotes are only for expression context" 
  }

-- | Quote a filename, without escaping any special characters.                                                
inputQ :: QuasiQuoter                                                
inputQ = quoteFile rawQ                                                
                                                
                                                
data QQConfig = QQConfig 
  { escaper :: ExpQ -> ExpQ }


parseE :: QQConfig -> String -> ExpQ
parseE cfg str = do
  let res = parseString parseLang (Columns 0 0) str
  case res of
    Failure xs -> do 
      runIO $ do
        displayIO stdout $ renderPretty 0.8 80 $ xs <> linebreak
        putStrLn "Due to parse failure entire quote will be processed as a string."
      joinE $ map (cvtE cfg) $ [StrPart str]
    Success x -> joinE $ map (cvtE cfg) x


cvtE :: QQConfig -> Component -> ExpQ
cvtE cfg (StrPart x)    = escaper cfg $ appE (varE 'T.pack) $ stringE x
cvtE cfg (EmbedShow x)  = 
  either (fallback "#" x) 
         (escaper cfg . appE [| T.pack . showJoin |] . return) $
  Meta.parseExp x
cvtE _   (EmbedMonad x) =  
  either (fallback "@" x) return $
  Meta.parseExp x

fallback :: String -> String -> String -> ExpQ
fallback sym str _ = [| esc . T.pack |] `appE` 
                   (stringE $ printf "%s{%s}" sym str)

trim :: String -> String
trim = T.unpack . T.strip . T.pack

showJoin :: Show a => a -> String
showJoin x = maybe sx id rsx
  where 
    sx :: String
    sx = show x
    rsx :: Maybe String
    rsx = readMay sx

joinE :: [ExpQ] -> ExpQ
joinE = foldl ap [e| return () |] 
  where
    ap a b = appE (appE (varE '(>>) ) a ) b

data Component 
  = StrPart    String
  | EmbedMonad String
  | EmbedShow  String deriving (Eq,Show)

parseLang :: Parser [Component]
parseLang = (many $ choice [try parseEmbedMonad, try parseEmbedShow, parseStrPart]) <* eof

parseStrPart :: Parser Component
parseStrPart = StrPart <$> go <?> "String Part"
  where
    go = do
      notFollowedBy $  choice [string "#{", string "@{"]
      h <- anyChar
      t <- manyTill anyChar (lookAhead $ choice [string "#{", string "@{", eof >> return ""])
      return $ h:t

parseEmbedMonad :: Parser Component
parseEmbedMonad = EmbedMonad <$> between (string "@{") (string "}") (some $ noneOf "}")
          <?> "Embed MonadAuthoring @{...}"


parseEmbedShow :: Parser Component
parseEmbedShow = EmbedShow <$> between (string "#{") (string "}") (some $ noneOf "}")
          <?> "Embed an instance of Show #{...}"


-- | Define a type and a 'Label' from the given name. We use Types to uniquely label concepts within a paper.
-- For example
--
-- > [declareLabels| myFormula |]
--
-- generates following three lines.
--
-- > data MyFormula = MyFormula deriving Typeable
-- > myFormula :: Label
-- > myFormula = fromValue MyFormula
--
-- You can declare multiple labels at one shot by separating them with a comma. 
--
-- > [declareLabels| FluxConservation, FaradayLaw, GaussLaw, AmpereLaw |]

declareLabels = 
 QuasiQuoter { 
  quoteExp  = error "defineLabel QuasiQuote is only for declaration context" ,  
  quotePat  = error "defineLabel QuasiQuote is only for declaration context" ,  
  quoteType = error "defineLabel QuasiQuote is only for declaration context" ,  
  quoteDec  = decLabelsQ
  }
 
 
decLabelsQ :: String -> DecsQ 
decLabelsQ str = fmap concat $ mapM decLabelQ names
  where
    names = 
      map T.unpack $
      map T.strip $
      T.splitOn "," $ T.pack str
              
              
decLabelQ :: String -> DecsQ
decLabelQ theName = do
  let (hName:tName) = theName
      theTypeName = mkName (toUpper hName : tName)
      theConName  = mkName (toUpper hName : tName)
      theValName  = mkName (toLower hName : tName)  
  
  let  decTheType = dataD (cxt []) theTypeName [] [normalC theConName []] [''Eq, ''Show, ''Typeable]                 
       typeTheVal = sigD theValName (conT ''Label)
       decTheVal = funD theValName [clause [] (normalB theBody) []]
       theBody = appE (varE 'fromValue) (conE theConName)
  sequence [decTheType, typeTheVal, decTheVal]
  


