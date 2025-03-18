#!/bin/bash

# Atualiza os pacotes do sistema
sudo apt-get update -y && sudo apt-get upgrade -y

# Instala pacotes essenciais
sudo apt-get install -y nfs-common python3 python3-pip python3-venv

# Por algum motivo o nfs-common vem mascarado, desfaça a máscara e inicia o serviço
sudo rm /lib/systemd/system/nfs-common.service
sudo systemctl daemon-reload
sudo systemctl enable nfs-common
sudo systemctl start nfs-common

# Instala o Amazon SSM Agent (para login via Session Manager)
sudo snap install amazon-ssm-agent --classic
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent

# Cria diretório do projeto na instância
sudo mkdir -p /home/ubuntu/wordpress
cd /home/ubuntu/wordpress

# Instalação do Amazon EFS Utils
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
. "$HOME/.cargo/env"
sudo apt-get update
sudo apt-get -y install git binutils rustc cargo pkg-config libssl-dev gettext
sudo git clone https://github.com/aws/efs-utils
cd efs-utils
sudo ./build-deb.sh
sudo apt-get -y install ./build/amazon-efs-utils*deb

# Cria o diretório para o EFS
sudo mkdir -p /mnt/efs

# Cria o script get_secret.py
cat <<EOF | sudo tee /home/ubuntu/wordpress/get_secret.py
import boto3
import json
import os
from botocore.exceptions import ClientError

def get_secret_value(secret_name, region_name="us-east-1"):
    client = boto3.client('secretsmanager', region_name=region_name)
    try:
        response = client.get_secret_value(SecretId=secret_name)
        if 'SecretString' in response:
            return json.loads(response['SecretString'])
        else:
            return None
    except ClientError as e:
        print(f"Erro ao acessar o segredo: {e}")
        return None

secret_name = "data_secret"
region = "us-east-1"
secret_data = get_secret_value(secret_name, region)

if secret_data:
    os.environ['EFS_ID'] = secret_data.get("EFS_ID", "")
    os.environ['RDS_HOST'] = secret_data.get("RDS_HOST", "")
    os.environ['RDS_PASSWORD'] = secret_data.get("RDS_PASSWORD", "")
    os.environ['RDS_ENDPOINT'] = secret_data.get("RDS_ENDPOINT", "")
    with open(".env", "w") as f:
        f.write(f"EFS_ID={os.environ['EFS_ID']}\n")
        f.write(f"RDS_HOST={os.environ['RDS_HOST']}\n")
        f.write(f"RDS_PASSWORD={os.environ['RDS_PASSWORD']}\n")
        f.write(f"RDS_ENDPOINT={os.environ['RDS_ENDPOINT']}\n")
    print("Segredos recuperados e salvos no arquivo '.env'.")
else:
    print("Falha ao recuperar o segredo.")
EOF

# Dá permissão de execução ao script
sudo chmod +x /home/ubuntu/wordpress/get_secret.py

# Limpeza do sistema
sudo apt-get clean

# Indica que a inicialização terminou
echo "Setup concluído!" > /tmp/setup_done
