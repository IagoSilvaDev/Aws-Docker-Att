#!/bin/bash

# Atualiza o sistema e instala dependências
sudo apt-get update -y
sudo apt-get upgrade -y

# Instalar docker e mysql-client
sudo apt-get install -y docker.io

# Verifica e habilita o nfs-common
sudo systemctl enable nfs-common
sudo systemctl start nfs-common

# Monta o EFS (substitua 'fs-XXXXXXXX' pelo ID do seu EFS)
sudo mount -t efs -o tls fs-XXXXXXXX:/ /mnt/efs

# Instala o Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Adiciona o usuário ao grupo docker (sem usar variáveis)
sudo usermod -aG docker ubuntu
newgrp docker

# Vai direto para o diretório do WordPress
cd /home/ubuntu/wordpress

# Cria o arquivo docker-compose.yml para o WordPress
sudo tee docker-compose.yml > /dev/null <<EOL
version: '3.8'

services:
  wordpress:
    image: wordpress:latest
    container_name: wordpress
    ports:
      - "80:80"
    environment:
      WORDPRESS_DB_HOST: {endpoint_do_RDS}
      WORDPRESS_DB_USER: admin
      WORDPRESS_DB_PASSWORD: {senha}
      WORDPRESS_DB_NAME: wordpress
    volumes:
      - /mnt/efs:/var/www/html
EOL

# Inicia o contêiner WordPress com Docker Compose
sudo docker-compose up -d

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
