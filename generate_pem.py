# Databricks notebook source
private_key_pass_raw = "<passphrase>" # passphrase for encryption .. could also be a keyvault secret
pempath = "<path to pem files>" # suggesting UC volume or DBFS

# COMMAND ----------

from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend
import re
import os

private_key_pass = private_key_pass_raw.encode('utf-8')


# Generate a private key
private_key = rsa.generate_private_key(
    public_exponent=65537,
    key_size=2048,
)

# Option to encrypt the private key (optional)
encrypted_pem_private_key = private_key.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.BestAvailableEncryption(private_key_pass),
)

# Generate the public key in PEM format
pem_public_key = private_key.public_key().public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo,
)



# COMMAND ----------

# Option to write keys to files
with open(pempath + "/rsa_key.p8", "wb") as f:
    f.write(encrypted_pem_private_key)

with open(pempath + "/rsa_key.pub", "wb") as f:
    f.write(pem_public_key)

# COMMAND ----------

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend
import re
import os

with open(pempath + "/rsa_key.p8", "rb") as key_file:
    private_key = serialization.load_pem_private_key(
        key_file.read(),
        password=private_key_pass,
        backend=default_backend()
    )
private_key_pem = private_key.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption()
).decode("utf-8")
private_key_hex64 = re.sub(r"-----.*-----|\n", "", private_key_pem)

with open(pempath + "/rsa_key-hex64.pem", "wb") as f:
    f.write(private_key_hex64.encode('utf-8'))




# COMMAND ----------

print("Private keys written to folder: ",pempath,"\n")

# Print the PEM encoded keys (for demonstration)

print("Private Key (PEM):\n", str(encrypted_pem_private_key.decode("utf-8"))) 
print("Public Key (PEM):\n", str(pem_public_key.decode("utf-8")))
print("Hex64 Key (PEM):\n")
print(private_key_hex64)