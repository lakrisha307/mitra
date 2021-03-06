-- I can't believe I have to do this
module Argh (seed_keypair) where

import           Control.Exception (handle, throw, SomeException)
import qualified Data.ByteString as S
import qualified Data.ByteString.Unsafe as SU
import           Foreign.C (CChar, CInt(..), CSize(..))
import           Foreign.Marshal.Alloc (mallocBytes, free)
import           Foreign.Ptr (Ptr)
import           System.IO.Unsafe (unsafePerformIO)

seed_keypair :: S.ByteString -> (S.ByteString, S.ByteString)
seed_keypair seed | S.length seed /= signSeed = error "seed has incorrect length"
          | otherwise = unsafePerformIO $ do
  pk <- mallocBytes signPK
  handle (\e -> free pk >> throw (e :: SomeException)) $ do
    sk <- mallocBytes signSK
    handle (\e -> free sk >> throw (e :: SomeException)) $
      SU.unsafeUseAsCString seed $ \pseed -> do
        0 <- c_sign_seed_keypair pk sk pseed
        bpk <- SU.unsafePackMallocCStringLen (pk, signPK)
        bsk <- SU.unsafePackMallocCStringLen (sk, signSK)
        return (bpk, bsk)

-- | The size of a public key for signing verification
signPK :: Int
signPK = fromIntegral c_crypto_sign_publickeybytes
-- | The size of a secret key for signing
signSK :: Int
signSK = fromIntegral c_crypto_sign_secretkeybytes
-- | The size of a seed for generating a keypair
signSeed :: Int
signSeed = fromIntegral c_crypto_sign_seedbytes

foreign import ccall "crypto_sign_seed_keypair"
  c_sign_seed_keypair :: Ptr CChar
                         -- ^ Public key output buffer
                         -> Ptr CChar
                         -- ^ Secret key output buffer
                         -> Ptr CChar
                         -- ^ Seed input buffer
                         -> IO CInt
                         -- ^ Always 0


foreign import ccall "crypto_sign_publickeybytes"
  c_crypto_sign_publickeybytes :: CSize

foreign import ccall "crypto_sign_secretkeybytes"
  c_crypto_sign_secretkeybytes :: CSize

foreign import ccall "crypto_sign_seedbytes"
  c_crypto_sign_seedbytes :: CSize
