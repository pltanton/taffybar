{-# OPTIONS_HADDOCK hide #-}
-----------------------------------------------------------------------------
-- |
-- Module      : System.Taffybar.Menu.Menu
-- Copyright   : 2017 Ulf Jasper
-- License     : BSD3-style (see LICENSE)
--
-- Maintainer  : Ulf Jasper <ulf.jasper@web.de>
-- Stability   : unstable
-- Portability : unportable
--
-- Implementation of version 1.1 of the freedesktop "Desktop Menu
-- Specification", see
-- https://specifications.freedesktop.org/menu-spec/menu-spec-1.1.html
--
-- See also 'MenuWidget'.
-----------------------------------------------------------------------------

module System.Taffybar.Menu.Menu (
  Menu(..),
  MenuEntry(..),
  buildMenu,
  getApplicationEntries)
where

import Data.Char (toLower)
import Data.List
import Data.Maybe
import System.Taffybar.Menu.DesktopEntry
import System.Taffybar.Menu.XdgMenu

-- | Displayable menu
data Menu = Menu {
  fmName            :: String,
  fmComment         :: String,
  fmIcon            :: Maybe String,
  fmSubmenus        :: [Menu],
  fmEntries         :: [MenuEntry],
  fmOnlyUnallocated :: Bool}
  deriving (Show)

-- | Displayable menu entry
data MenuEntry = MenuEntry {
  feName    :: String,
  feComment :: String,
  feCommand :: String,
  feIcon    :: Maybe String}
  deriving (Eq, Show)


-- | Fetch menus and desktop entries and assemble the menu.
buildMenu :: Maybe String -> IO Menu
buildMenu mMenuPrefix = do
  mMenuDes <- readXdgMenu mMenuPrefix
  case mMenuDes of
    Nothing          -> return $ Menu "???" "Parsing failed" Nothing [] [] False
    Just (menu, des) -> do dt <- getXdgDesktop
                           dirDirs <- getDirectoryDirs
                           langs <- getPreferredLanguages
                           (fm, ae) <- xdgToMenu dt langs dirDirs des menu
                           let fm' = fixOnlyUnallocated ae fm
                           return fm'

-- | Convert xdg menu to displayable menu
xdgToMenu :: String -> [String] -> [FilePath] -> [DesktopEntry] -> XdgMenu
          -> IO (Menu, [MenuEntry])
xdgToMenu desktop langs dirDirs des xm = do
  dirEntry <- getDirectoryEntry (xmDirectory xm) dirDirs
  mas <- mapM (xdgToMenu desktop langs dirDirs des) (xmSubmenus xm)
  let (menus, subaes) = unzip mas
      menus' = sortBy (\fm1 fm2 -> compare (map toLower $ fmName fm1)
                                   (map toLower $ fmName fm2)) menus
      entries = map (xdgToMenuEntry langs) $
                -- hide NoDisplay
                filter (not . deNoDisplay) $
                -- onlyshowin
                filter (matchesOnlyShowIn desktop) $
                -- excludes
                filter (not . flip matchesCondition (fromMaybe None (xmExclude xm))) $
                -- includes
                filter (flip matchesCondition (fromMaybe None (xmInclude xm))) des
      onlyUnallocated = xmOnlyUnallocated xm
      aes = if onlyUnallocated then [] else entries ++ concat subaes
  let fm = Menu {fmName            = maybe (xmName xm) (deName langs) dirEntry,
                 fmComment         = maybe "???" (fromMaybe "???" . deComment langs) dirEntry,
                 fmIcon            = deIcon =<< dirEntry,
                 fmSubmenus        = menus',
                 fmEntries         = entries,
                 fmOnlyUnallocated = onlyUnallocated}
  return (fm, aes)

-- | Check the "only show in" logic
matchesOnlyShowIn :: String -> DesktopEntry -> Bool
matchesOnlyShowIn desktop de = matchesShowIn && notMatchesNotShowIn
  where matchesShowIn = case deOnlyShowIn de of
                          [] -> True
                          desktops -> desktop `elem` desktops
        notMatchesNotShowIn = case deNotShowIn de of
                                [] -> True
                                desktops -> not $ desktop `elem` desktops

-- | convert xdg desktop entry to displayble menu entry
xdgToMenuEntry :: [String] -> DesktopEntry -> MenuEntry
xdgToMenuEntry langs de = MenuEntry {feName     = name,
                                      feComment = comment,
                                      feCommand = cmd,
                                      feIcon    = mIcon}
  where mc = case deCommand de of
               Nothing -> Nothing
               Just c  -> Just $ "(" ++ c ++ ")"
        comment = fromMaybe "??" $ case deComment langs de of
                                     Nothing -> mc
                                     Just tt -> Just $ tt ++ maybe "" ("\n" ++) mc
        cmd = fromMaybe "FIXME" $ deCommand de
        name = deName langs de
        mIcon = deIcon de

-- | postprocess unallocated entries
fixOnlyUnallocated :: [MenuEntry] -> Menu -> Menu
fixOnlyUnallocated fes fm = fm {fmEntries = entries,
                                fmSubmenus = map (fixOnlyUnallocated fes) (fmSubmenus fm)}
  where entries = if (fmOnlyUnallocated fm)
                  then filter (not . (`elem` fes)) (fmEntries fm)
                  else fmEntries fm
