{-
Copyright (C) 2008 John MacFarlane <jgm@berkeley.edu>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

module Main where

import Network.Gitit
import Network.Gitit.Server
import Network.Gitit.Initialize (createStaticIfMissing, createRepoIfMissing)
import Prelude hiding (writeFile, readFile, catch)
import System.Directory
import System.FilePath ((</>))
import Network.Gitit.Config (getConfigFromOpts)
import Data.Maybe (isNothing)
import Control.Monad.Reader
import System.Log.Logger (logM, Priority(..), setLevel, setHandlers,
        getLogger, saveGlobalLogger)
import System.Log.Handler.Simple (fileHandler)
import Data.Char (toLower)

main :: IO ()
main = do

  -- parse options to get config file
  conf <- getConfigFromOpts

  -- check for external programs that are needed
  let repoProg = map toLower $ show $ repositoryType conf
  let prereqs = ["grep", repoProg]
  forM_ prereqs $ \prog ->
    findExecutable prog >>= \mbFind ->
    when (isNothing mbFind) $ error $
      "Required program '" ++ prog ++ "' not found in system path."

  -- set up logging
  let level = if debugMode conf then DEBUG else logLevel conf
  logFileHandler <- fileHandler (logFile conf) level
  serverLogger <- getLogger "Happstack.Server.AccessLog.Combined"
  gititLogger <- getLogger "gitit"
  saveGlobalLogger $ setLevel level $ setHandlers [logFileHandler] serverLogger
  saveGlobalLogger $ setLevel level $ setHandlers [logFileHandler] gititLogger

  jsMathExists <- liftIO $ doesFileExist $
                  staticDir conf </> "js" </> "jsMath" </> "easy" </> "load.js"
  logM "gitit" NOTICE $
    if jsMathExists
       then "Found jsMath scripts -- using jsMath"
       else "Did not find jsMath scripts -- not using jsMath"

  let conf' = conf{jsMath = jsMathExists, logLevel = level}  

  -- initialize state
  initializeGititState conf'

  -- setup the page repository, template, and static files, if they don't exist
  createRepoIfMissing conf'
  createStaticIfMissing conf'
  createTemplateIfMissing conf'

  let serverConf = Conf { validator = Nothing, port = portNumber conf' }
  -- start the server
  simpleHTTP serverConf $ msum [
      wikiHandler conf'
    , dir "_reloadTemplates" reloadTemplates
    ]
