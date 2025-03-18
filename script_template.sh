#!/bin/bash

# Atualiza o sistema e instala dependências
sudo apt-get update -y
sudo apt-get upgrade -y

# Instalar docker e mysql-client
sudo apt-get install -y docker.io

# Verifica e habilita o nfs-common
sudo systemctl enable nfs-common
sudo systemctl start nfs-common

# Configura ambiente Python e instala boto3
sudo apt-get install -y python3 python3-pip python3-venv
sudo python3 -m venv /home/ubuntu/venv
source /home/ubuntu/venv/bin/activate
pip install boto3

# Executa o script get_secret.py para buscar as variáveis do Secrets Manager
cd /home/ubuntu/wordpress
sudo /home/ubuntu/venv/bin/python3 get_secret.py

# Carrega as variáveis do ambiente do arquivo .env
set -a  # Habilita exportação automática das variáveis
source /home/ubuntu/wordpress/.env
set +a  # Desabilita exportação automática após carregar

# Monta o EFS com a variável obtida
sudo mount -t efs -o tls $EFS_ID:/ /mnt/efs

# Instala o Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Adiciona o usuário ao grupo docker
sudo usermod -aG docker ubuntu
newgrp docker

# Vai direto para o diretório do WordPress
cd /home/ubuntu/wordpress

# Cria o arquivo docker-compose.yml substituindo as variáveis coletadas
sudo tee docker-compose.yml > /dev/null <<EOL
version: '3.8'

services:
  wordpress:
    image: wordpress:latest
    container_name: wordpress
    ports:
      - "80:80"
    environment:
      WORDPRESS_DB_HOST: $RDS_ENDPOINT
      WORDPRESS_DB_USER: $RDS_HOST
      WORDPRESS_DB_PASSWORD: $RDS_PASSWORD
      WORDPRESS_DB_NAME: wordpress
    volumes:
      - /mnt/efs:/var/www/html
EOL

# Cria um serviço systemd para garantir que o Docker Compose suba automaticamente após reboot
sudo tee /etc/systemd/system/wordpress.service > /dev/null <<EOL
[Unit]
Description=Docker Compose WordPress Service
Requires=docker.service
After=docker.service

[Service]
WorkingDirectory=/home/ubuntu/wordpress
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
Restart=on-failure
RestartSec=5s
User=root
Type=oneshot
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target

EOL

# Recarrega o systemd e habilita o serviço
sudo systemctl daemon-reload
sudo systemctl enable wordpress.service
sudo systemctl start wordpress.service

# Aguarda o container WordPress estar ativo
echo "Aguardando o container WordPress iniciar..."
until sudo docker ps | grep -q "Up.*wordpress"; do
  echo "Verificando containers em execução..."
  sudo docker ps
  sleep 5
done
echo "Container WordPress iniciado!"

# Adiciona o arquivo healthcheck.php no contêiner WordPress
echo "Criando o arquivo healthcheck.php no contêiner WordPress..."
sudo docker exec -i wordpress bash -c "cat <<EOF > /var/www/html/healthcheck.php
<?php
http_response_code(200);
header('Content-Type: application/json');
echo json_encode([\"status\" => \"OK\", \"message\" => \"Health check passed\"]);
exit;
?>
EOF"
