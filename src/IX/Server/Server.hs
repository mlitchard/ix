{-# LANGUAGE OverloadedStrings, RecordWildCards, LambdaCase #-}

module IX.Server.Server
  (server)
  where

import           DataStructures.Composite
import           DataStructures.Atomic
import           IX.Universe.Input
import           IX.Reactive.EventNetwork (gameloop)
import           Conduit
import           Data.Conduit
import           Data.Functor ((<$>))
import           Data.Conduit.TMChan
import           Control.Concurrent.STM
import qualified Data.Map.Strict       as M
import qualified Data.Text             as T
import           Control.Monad.IO.Class
import           Data.Conduit.Network
import qualified Data.ByteString.Char8 as BS
import           Text.Printf              (printf)
import           Data.Word8               (_cr)
import           Control.Monad
import           Control.Concurrent.Async (concurrently)
import           Control.Exception        (finally)

server :: Int -> IO ()
server port' = do
  server <- newServer
  runTCPServer (serverSettings port' "*") $ \app -> do
    (fromClient, client) <-
      appSource app $$+ readName server app `fuseUpstream` appSink app
    print (clientName client)
    (runClient fromClient server client) `finally` (removeClient server client)

clientSink :: Client -> Sink BS.ByteString IO ()
clientSink Client{..} = mapC SCommand =$ sinkTMChan clientChan True


newServer :: IO Server
newServer = do
  cs  <- newTVarIO M.empty
  cns <- newTVarIO M.empty
  gsc <- newTChanIO 
  cc  <- newTChanIO
  go  <- newTVarIO False
  return 
    Server { 
       clients       = cs
     , clientNames   = cns
     , gameStateChan = gsc
     , commandChan   = cc
     , gameon        = go
    }

readName :: Server -> AppData -> ConduitM BS.ByteString BS.ByteString IO Client
readName server app = go
  where
  go = do
    yield "What is your game name? " $$ appSink app
    name <- lineAsciiC $ takeCE 80 =$= filterCE (/= _cr) =$= foldC
    if BS.null name then
      go
    else do
      ok <- liftIO $ checkAddClient server name app
      case ok of
        Nothing -> do
          respond "The name '%s' is in use, please choose another\n" name
          go
        Just client -> do
          respond "Welcome, %s!\n" name
          return client
  respond msg name = yield $ BS.pack $ printf msg $ BS.unpack name

checkAddClient :: Server -> ClientName -> AppData -> IO (Maybe Client)
checkAddClient server@Server{..} name app = atomically $ do
  clientmap <- readTVar clients
  if M.member name clientmap then
    return Nothing
  else do
    camap  <- readTVar clientNames -- maps aid to name
    let aid = AID (T.pack $ show $ (((M.size camap) -1) + 100))
    client <- newClient name app
    writeTVar clients (M.insert name client clientmap)
    writeTVar clientNames    (M.insert aid name camap)
    broadcast server  (Notice (name <++> " has connected"))
    return (Just client)

broadcast :: Server -> SMessage -> STM ()
broadcast Server{..} msg = do
  clientmap <- readTVar clients
  mapM_ (\client -> sendMessage client msg) (M.elems clientmap)

runClient :: ResumableSource IO BS.ByteString -> Server -> Client -> IO ()
runClient clientSource server client@Client{..} =
  void $ concurrently
  (clientSource $$+- linesUnboundedAsciiC =$ clientSink client)
  (sourceTMChan clientChan $$ handleMessage server client =$ appSink clientApp)

removeClient :: Server -> Client -> IO ()
removeClient server@Server{..} client@Client{..} = atomically $ do
  modifyTVar' clients (M.delete clientName)
  modifyTVar' clientNames (M.filter (== clientName))
  broadcast server $ Notice (clientName <++> " has disconnected")

sendMessage :: Client -> SMessage -> STM ()
sendMessage Client{..} msg = writeTMChan clientChan msg

listClients :: Server -> STM [ClientName]
listClients Server{..} = do
  c <- readTVar clients
  return $ M.keys c

newClient :: ClientName -> AppData -> STM Client
newClient name app = do
  chan <- newTMChan
  return Client { clientName     = name
                , clientApp      = app
                , clientChan     = chan
                }

sendToName :: Server -> ClientName -> SMessage -> STM Bool
sendToName server@Server{..} name msg = do
  clientmap <- readTVar clients
  case M.lookup name clientmap of
      Nothing -> return False
      Just client -> sendMessage client msg >> return True

handleMessage :: Server -> Client -> Conduit SMessage IO BS.ByteString
handleMessage server client@Client{..} = awaitForever $ \case
  Notice msg         -> output $ "*** " <++> msg
  Tell name msg      -> output $ "*" <++> name <++> "*: " <++> msg
  Broadcast name msg -> output $ "<" <++> name <++> ">: " <++> msg
  SCommand msg       -> case BS.words msg of
    ["/start"] -> do
      ok <- liftIO $ atomically $ gameManager server
      unless ok $ output $ "Game already started"
    
    ["/tell", who, what] -> do
      ok <- liftIO $ atomically $ sendToName server who $ Tell clientName what
      unless ok $ output $ who <++> " is not connected."
    ["/help"] ->
      mapM_ output [ "------ help -----"
                   , "/start - starts a new game"
                   , "/shout <message> - Everyone needs to know eh?"
                   , "/tell <who> <what> - send a private message"
                   , "/list - list users online"
                   , "/help - show this message"
                   , "/quit - leave"
                   ]
    ["/list"] -> do
      cl <- liftIO $ atomically $ listClients server
      output $ BS.concat $ "----- online -----\n" : map ((flip BS.snoc) '\n') cl
    ["/quit"] -> do
      error . BS.unpack $ clientName <++> " has quit"
    ["/shout"] -> do
      liftIO $ atomically $ broadcast server $ Broadcast clientName msg
        -- ignore empty strings
    [""] -> return ()
    [] -> return ()

        -- broadcasts
    ws ->
      if BS.head (head ws) == '/' then
        output $ "Unrecognized command: " <++> msg
      else
        liftIO $ atomically $ commandManager server $ GCommand clientName msg
  where
    output s = yield (s <++> "\n")

(<++>) = BS.append

gameManager server@Server{..} = do
  gameStarted <- readTVar gameon
  anMap       <- readTVar clientNames
  aids        <- M.keys <$> readTVar clientNames
  if gameStarted == True then
    return gameStarted
  else do
    let anMap_keys = M.keys anMap
        newMaps    = initMaps anMap anMap_keys
        initMaps   =
          InitMaps {
              aMap = initAmap anMap  
            , pMap = initPmap aids
            , lMap = initLmap aids
          } 
    _ <- gameloop commandChan gameStateChan newMaps
    return True
commandManager = undefined
