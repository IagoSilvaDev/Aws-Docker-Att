import boto3
import json
import os
from botocore.exceptions import ClientError

def get_secret_value(secret_name, region_name="us-east-1"):
    # Criar cliente do AWS Secrets Manager
    client = boto3.client('secretsmanager', region_name=region_name)

    try:
        # Obter o segredo
        response = client.get_secret_value(SecretId=secret_name)

        # Verifica se o segredo é uma string JSON
        if 'SecretString' in response:
            return json.loads(response['SecretString'])  # Retorna o JSON como dicionário
        else:
            return None
       
    except ClientError as e:
        print(f"Erro ao acessar o segredo: {e}")
        return None

# Nome do segredo e região
secret_name = "nome-do-seu-segredo"
region = "us-east-1"

# Recupera os valores do segredo
secret_data = get_secret_value(secret_name, region)

if secret_data:
    # Salva os valores individuais em variáveis de ambiente
    os.environ['EFS_ID'] = secret_data.get("EFS_ID", "")
    os.environ['RDS_HOST'] = secret_data.get("RDS_HOST", "")
    os.environ['RDS_PASSWORD'] = secret_data.get("RDS_PASSWORD", "")
    os.environ['RDS_ENDPOINT'] = secret_data.get("RDS_ENDPOINT", "")

    # Escreve as variáveis no arquivo .env
    with open(".env", "w") as f:
        f.write(f"EFS_ID={os.environ['EFS_ID']}\n")
        f.write(f"RDS_HOST={os.environ['RDS_HOST']}\n")
        f.write(f"RDS_PASSWORD={os.environ['RDS_PASSWORD']}\n")
        f.write(f"RDS_ENDPOINT={os.environ['RDS_ENDPOINT']}\n")

    print("Segredos recuperados e salvos no arquivo '.env'.")
else:
    print("Falha ao recuperar o segredo.")
