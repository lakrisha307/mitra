{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Applicative (pure, (<$>), (<*>))
import Control.Monad (replicateM, unless)
import Control.Exception (assert)
import Debug.Trace (traceShow)
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Base64 as B64
import Data.ByteString.Lazy (toStrict, fromStrict)
import Data.Binary.Get (Get, runGet, getByteString, getWord32be, getRemainingLazyByteString)

runStrictGet :: Get c -> B.ByteString -> c
runStrictGet = (. fromStrict) . runGet

data KeyBox = KeyBox
              { ciphername :: B.ByteString
              , kdfname :: B.ByteString
              , kdfoptions :: B.ByteString
              , boxKeys :: [Key]
              } deriving (Show)

auth_magic :: B.ByteString
auth_magic = "openssh-key-v1\000"

expected_padding :: B.ByteString
expected_padding = BC.pack ['\001'..'\377']

data Key = PublicKey
           { keyAlg :: B.ByteString
           , publicKeyData :: B.ByteString
           }
         | PrivateKey
           { privateKeyAlg :: B.ByteString
           , publicKeyData :: B.ByteString
           , privateKeyData :: B.ByteString
           , comment :: B.ByteString
           }
         deriving (Show)

dearmorPrivateKey :: B.ByteString -> Either String B.ByteString
dearmorPrivateKey =
    B64.decode
    . B.concat
    . takeWhile (/= "-----END OPENSSH PRIVATE KEY-----")
    . drop 1
    . dropWhile (/= "-----BEGIN OPENSSH PRIVATE KEY-----")
    . BC.lines

getPascalString :: Get B.ByteString
getPascalString = do
  len <- getWord32be
  getByteString (fromIntegral len)

getKeyBox :: Get KeyBox
getKeyBox = do
  magic <- getByteString (B.length auth_magic)
  unless (magic == auth_magic) (fail "Magic does not match")
  cn <- getPascalString
  unless (cn == "none") (fail "Unsupported cipher")
  kn <- getPascalString
  unless (kn == "none") (fail "Unsupported kdf")
  ko <- getPascalString
  unless (ko == "") (fail "Invalid kdf options")
  keys <- do
    count <- fromIntegral <$> getWord32be
    -- Parse the private keys, but throw them away
    replicateM count (runStrictGet getPublicKey <$> getPascalString)
    privateKeys <- runStrictGet (getPrivateKeys count) <$> getPascalString
    return privateKeys
  return $ KeyBox cn kn ko keys

getPublicKey :: Get Key
getPublicKey = PublicKey <$> getPascalString <*> getPascalString

getPrivateKey :: Get Key
getPrivateKey = PrivateKey
  <$> getPascalString
  <*> getPascalString
  <*> getPascalString
  <*> getPascalString

getPrivateKeys :: Int -> Get [Key]
getPrivateKeys count = do
  checkint1 <- getWord32be
  checkint2 <- getWord32be
  unless (checkint1 == checkint2) (fail "Decryption failed")
  keys <- replicateM count getPrivateKey
  padding <- toStrict <$> getRemainingLazyByteString
  unless (B.take (B.length padding) expected_padding == (traceShow padding padding)) (fail "Incorrect padding")
  return keys

parseKeyBox :: B.ByteString -> KeyBox
parseKeyBox = runStrictGet getKeyBox

main :: IO ()
main = do
  contents <- B.getContents
  box <- either error pure $ do
    b <- dearmorPrivateKey contents
    return . parseKeyBox $ b
  putStrLn $ show box