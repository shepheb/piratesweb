{-# LANGUAGE TemplateHaskell, QuasiQuotes, TypeFamilies #-}


module Main where

import Yesod
import Yesod.Helpers.Static

import Control.Concurrent.STM
import Control.Concurrent.STM.TChan
import Control.Concurrent.STM.TVar

import Control.Arrow ((***))

-- speaker and content
data Message = Message String String

-- all those TChans are dupes, so writing to any one writes to them all, but reading is separate
data Chat = Chat
  { chatClients    :: TVar [(Int, TChan Message)]
  , nextClient     :: TVar Int
  , chatStatic     :: Static
  }

staticFiles "static"

mkYesod "Chat" [$parseRoutes|
/          HomeR   GET
/check     CheckR  GET
/post      PostR   GET
/static    StaticR Static chatStatic
|]

instance Yesod Chat where
  approot _ = ""
  defaultLayout content = hamletToContent [$hamlet|
    !!!
    %html
        %head
            %title $pageTitle.content$
            %script!src="http://ajax.googleapis.com/ajax/libs/jquery/1.4.2/jquery.min.js"
            %script!src=@StaticR.chat_js@
            ^pageHead.content^
        %body
            ^pageBody.content^
    |]


getHomeR :: Handler Chat RepHtml
getHomeR = do
  Chat clients next _ <- getYesod
  client <- liftIO . atomically $ do
    c <- readTVar next
    writeTVar next (c+1)
    cs <- readTVar clients
    chan <- case cs of
              []      -> newTChan
              (_,x):_ -> dupTChan x
    writeTVar clients ((c,chan) : cs)
    return c
  applyLayout "Chat Page" mempty [$hamlet|
    !!!
    %h1 Chat Example
    %form
        %textarea!cols=80!rows=20!name=chat
        %p
            %input!type=text!size=15!name=name#name
            %input!type=text!size=60!name=send#send
            %input!type=submit!value=Send
    <script language="javascript"> var clientNumber = $show client$ </script>
    |]

    

getCheckR :: Handler Chat RepJson
getCheckR = do
  liftIO $ putStrLn "Check"
  Chat clients _ _ <- getYesod
  client <- do
    c <- lookupGetParam "client"
    case c of
      Nothing -> invalidArgs ["No client value in Check request"]
      Just c' -> return $ read c'
  cs <- liftIO . atomically $ readTVar clients
  chan <- case lookup client cs of
            Nothing -> invalidArgs ["Bad client value"]
            Just ch -> return ch
  -- block until there's something there
  first <- liftIO . atomically $ readTChan chan
  let Message s c = first
  jsonToRepJson $ zipJson ["sender", "content"] [s,c]


zipJson x y = jsonMap $ map (id *** (jsonScalar.string)) $ zip x y


getPostR :: Handler Chat RepJson
getPostR = do
  liftIO $ putStrLn "Post"
  Chat clients _ _ <- getYesod
  (sender,content) <- do
    s <- lookupGetParam "name"
    c <- lookupGetParam "send"
    case (s,c) of
      (Just s', Just c') -> return (s', c')
      _                  -> invalidArgs ["Either name or send not provided."]
  liftIO . atomically $ do
    cs <- readTVar clients
    let chan = snd . head $ cs -- doesn't matter which one we use, they're all duplicates
    writeTChan chan (Message sender content)
  
  jsonToRepJson $ jsonScalar (string "success")
  

main :: IO ()
main = do
  clients <- newTVarIO []
  next <- newTVarIO 0
  let static = fileLookupDir "static" typeByExt
  basicHandler 3000 $ Chat clients next static

