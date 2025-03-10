#!/bin/bash

# Atualiza os pacotes do sistema
sudo apt-get update -y && sudo apt-get upgrade -y

# Instala pacotes essenciais
sudo apt-get install -y nfs-common

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

# Limpeza do sistema
sudo apt-get clean

# Indica que a inicialização terminou
echo "Setup concluído!" > /tmp/setup_done
