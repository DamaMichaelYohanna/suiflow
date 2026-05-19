import base64
import os

# Secret master key to simulate KMS key wrapping.
# In a production environment, this key is retrieved from a secure Enclave or Cloud KMS service (e.g. AWS KMS / Google Cloud KMS).
KMS_MASTER_KEY = os.environ.get("SUIFLOW_KMS_MASTER_KEY", "hackathon_secret_kms_master_key_2026")

def encrypt_private_key(raw_keystring: str) -> str:
    """
    Simulates KMS Key Envelope Encryption.
    Encrypts a raw Sui private key (keystring) using the master key.
    """
    key_bytes = KMS_MASTER_KEY.encode('utf-8')
    raw_bytes = raw_keystring.encode('utf-8')
    
    # Simple XOR cipher for dependency-free deployment
    encrypted_bytes = bytearray()
    for i in range(len(raw_bytes)):
        encrypted_bytes.append(raw_bytes[i] ^ key_bytes[i % len(key_bytes)])
        
    return base64.b64encode(encrypted_bytes).decode('utf-8')

def decrypt_private_key(encrypted_keystring: str) -> str:
    """
    Simulates KMS Key Decryption.
    Decrypts the encrypted Sui private key from the database using the master key.
    """
    key_bytes = KMS_MASTER_KEY.encode('utf-8')
    encrypted_bytes = base64.b64decode(encrypted_keystring.encode('utf-8'))
    
    decrypted_bytes = bytearray()
    for i in range(len(encrypted_bytes)):
        decrypted_bytes.append(encrypted_bytes[i] ^ key_bytes[i % len(key_bytes)])
        
    return decrypted_bytes.decode('utf-8')
