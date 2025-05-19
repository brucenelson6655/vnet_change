PYTHONCMD=python3

mkdir -p pem/archive
cd pem

export PASSPHR=$1

if [ -z $PASSPHR ]
then 
  echo "Usage : $0 <passphrase>"
  echo "please provide passphrase"
  exit
fi

cp -v rsa_key* archive/.

openssl genrsa 2048 | openssl pkcs8 -topk8 -v2 des3 -inform PEM -out rsa_key.p8 -passout env:PASSPHR

openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub -passin env:PASSPHR


${PYTHONCMD} -c '
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend
import re
import os

passphr = os.environ["PASSPHR"]

with open("rsa_key.p8", "rb") as key_file:
    private_key = serialization.load_pem_private_key(
        key_file.read(),
        password=passphr.encode(),
        backend=default_backend()
    )
private_key_pem = private_key.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption()
).decode("utf-8")
private_key_hex64 = re.sub(r"-----.*-----|\n", "", private_key_pem)
outfile = open("rsa_key-hex64.pem", "w")
print(private_key_hex64, file = outfile)
'
ls -l rsa_*
export PASSPHR=''
echo done