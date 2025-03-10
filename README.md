# Aws-Docker-Att

Este projeto configura uma infraestrutura na AWS para hospedar o WordPress usando Docker, com balanceamento de carga, escalonamento automático e armazenamento compartilhado via Amazon EFS.

## 🛠 Tecnologias Utilizadas

- **AWS VPC** – Rede isolada para os recursos da aplicação.
- **AWS ALB (Application Load Balancer)** – Distribuição de tráfego entre as instâncias.
- **AWS EC2 (Auto Scaling Group)** – Instâncias que executam contêineres Docker com o WordPress.
- **Docker** – Containerização da aplicação WordPress.
- **Amazon RDS (MySQL)** – Banco de dados gerenciado para armazenamento persistente.
- **Amazon EFS** – Sistema de arquivos compartilhado entre as instâncias do WordPress.
- **Amazon IAM** – Serviço de gerenciamento de permissões e identidade na AWS.

##  Requisitos para Execução

Antes de iniciar a implantação, certifique-se de ter o seguinte requisito:

- **Conta AWS** com permissões para utilizar recursos como VPC, IAM, EC2, ALB, RDS e EFS.

##  Instalação e Execução

### 1️⃣ Criando a Role no IAM e Configurando Session Manager

Para permitir que as instâncias EC2 utilizem o AWS Systems Manager (Session Manager) e acessem o Amazon EFS, é necessário criar uma Role no IAM com as permissões adequadas.

1. **Acesse o Console da AWS** e vá até o serviço **IAM**.
2. No menu lateral, clique em **Roles** e depois em **Create Role**.
3. Em **Trusted Entity Type**, selecione **AWS Service** e escolha **EC2**.
4. Clique em **Next** para adicionar as permissões.
5. Adicione as seguintes políticas:
   - **AmazonSSMManagedInstanceCore** → Permite acesso via AWS Systems Manager (Session Manager).
   - **AmazonElasticFileSystemFullAccess** → Permite que a instância EC2 utilize o EFS.
7. Confirmque que sua Trusted Policy está desse jeito abaixo:
   ```json
   {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
     ]
   }
   
8. Clique em **Next**, defina um nome para a Role (ex: `EC2_SSM_EFS_Role`) e finalize a criação.

Após isso, esta Role poderá ser anexada às instâncias EC2 durante a configuração da infraestrutura.

#### 🔹 Configurando o Session Manager

1. **Acesse o Console da AWS** e vá até **Systems Manager > Session Manager**.
2. No menu lateral, clique em **Preferences**.
3. Em **Shell Profile**, adicione o seguinte comando no campo de configuração:
   ```bash
   sudo su ubuntu
Com isso Logaremos no usuário ubuntu sempre que iniciarmos uma sessão.

Após isso, esta Role poderá ser anexada às instâncias EC2 durante a configuração da infraestrutura.

### 2️⃣ Criando a VPC e Configuração de Rede

A VPC será configurada para fornecer comunicação segura entre os serviços da AWS, com sub-redes públicas e privadas, além de gateways para permitir a conectividade externa.

---

#### 🔹 Criando a VPC

1. Acesse o **AWS Console** e vá até o serviço **VPC**.
2. Clique em **Create VPC** e forneça as seguintes configurações:
   - **Nome**: `WordPressVPC`
   - **IPv4 CIDR Block**: `10.1.1.0/24` *(faixa de IPs para a VPC)*
   - **Tenancy**: `Default`
3. Clique em **Create VPC**.

---

#### 🔹 Criando as Subnets

Agora, criaremos **4 subnets**, sendo **2 públicas** (para o Load Balancer) e **2 privadas** (para as instâncias EC2 e banco de dados).

1. No painel do serviço **VPC**, vá para **Subnets** e clique em **Create subnet**.
2. Selecione a **VPC criada anteriormente (`WordPressVPC`)** e adicione as subnets conforme abaixo:

   | Nome             | CIDR Block      | Zona de Disponibilidade | Tipo    |
   |-----------------|----------------|-------------------------|---------|
   | PublicSubnet1   | `10.1.1.32/28`   | `us-east-1a`            | Pública |
   | PublicSubnet2   | `10.1.1.48/28`   | `us-east-1b`            | Pública |
   | PrivateSubnet1  | `10.1.1.128/28`   | `us-east-1a`            | Privada |
   | PrivateSubnet2  | `10.1.1.144/28`   | `us-east-1b`            | Privada |

3. Após adicionar todas as subnets, clique em **Create Subnet**.

---

#### 🔹 Criando e Associando as Route Tables

Agora, criaremos duas Route Tables:
- Uma para as **subnets públicas**, permitindo acesso à internet via **Internet Gateway**.
- Outra para as **subnets privadas**, permitindo acesso externo via **NAT Gateway**.

1. Vá até **Route Tables** no serviço **VPC** e clique em **Create route table**.
2. Configure a primeira tabela de rotas:
   - **Nome**: `PublicRouteTable`
   - **VPC**: `WordPressVPC`
   - Clique em **Create**.

3. Configure a segunda tabela de rotas:
   - **Nome**: `PrivateRouteTable`
   - **VPC**: `WordPressVPC`
   - Clique em **Create**.

4. Agora, associe as subnets:
   - Selecione a **PublicRouteTable**, clique na aba **Subnet Associations** e associe `PublicSubnet1` e `PublicSubnet2`.
   - Selecione a **PrivateRouteTable**, clique na aba **Subnet Associations** e associe `PrivateSubnet1` e `PrivateSubnet2`.

---

#### 🔹 Criando o Internet Gateway e Associando à Route Table Pública

1. No painel do serviço **VPC**, vá para **Internet Gateways** e clique em **Create Internet Gateway**.
   - **Nome**: `WordPressIGW`
   - Clique em **Create**.
2. Selecione o **WordPressIGW**, clique em **Attach to a VPC** e escolha `WordPressVPC`.
3. Agora, vá para **Route Tables**, selecione **PublicRouteTable**, clique na aba **Routes** e adicione uma nova rota:
   - **Destination**: `0.0.0.0/0`
   - **Target**: `Internet Gateway (WordPressIGW)`
4. Clique em **Save Routes**.

---

#### 🔹 Criando o NAT Gateway e Associando à Route Table Privada

O **NAT Gateway** permite que as instâncias privadas tenham acesso à internet para baixar pacotes e atualizações.

1. Vá até **NAT Gateways** e clique em **Create NAT Gateway**.
2. Configure:
   - **Subnet**: `PublicSubnet1` *(precisa estar em uma subnet pública)*
   - **Elastic IP**: Clique em **Allocate Elastic IP** e selecione-o.
   - Clique em **Create NAT Gateway**.
3. Vá para **Route Tables**, selecione **PrivateRouteTable**, clique na aba **Routes** e adicione:
   - **Destination**: `0.0.0.0/0`
   - **Target**: `NAT Gateway (WordPressNAT)`.
4. Clique em **Save Routes**.

---

Agora, sua **VPC está configurada** com subnets públicas e privadas, permitindo a comunicação interna e o acesso externo conforme necessário.  


### 3️⃣ Criando os Security Groups

Os **Security Groups (SGs)** controlam o tráfego de entrada e saída dos recursos na VPC. Para este projeto, criaremos os seguintes SGs:

1. **SG para o Load Balancer** (`LB-SG`)
2. **SG para as instâncias EC2** (`EC2-SG`)
3. **SG para o banco de dados RDS** (`RDS-SG`)
4. **SG para o Amazon EFS** (`EFS-SG`)

---

#### 🔹 Criando os Security Groups

1. Acesse o **AWS Console**, vá para **EC2 > Security Groups** e clique em **Create Security Group**.
2. Para cada Security Group, preencha os seguintes campos:

| Nome      | Descrição | VPC |
|-----------|----------|-----|
| `LB-SG`  | Fica a seu critério| `WordPressVPC` |
| `EC2-SG`  | Fica a seu critério | `WordPressVPC` |
| `RDS-SG`  | Fica a seu critério | `WordPressVPC` |
| `EFS-SG`  | Fica a seu critério | `WordPressVPC` |

3. Após criar todos os SGs, prossiga para a configuração das **regras de entrada e saída**.

---

#### 🔹 Configurando as Regras dos Security Groups

Agora, ajustamos as regras de **ingresso (inbound)** e **saída (outbound)** para cada Security Group.

##### 📌 Regras para `LB-SG` (Load Balancer)
| Tipo      | Protocolo | Porta  | Origem |
|-----------|----------|--------|--------|
| ALL Traffic | ALL     | ALL    | 0.0.0.0/0 (Aceita todo tráfego de entrada) |

- **Outbound (Saída):**  
  | Tipo  | Protocolo | Porta | Destino |
  |-------|----------|------|---------|
  | HTTP  | TCP      | 80   | `EC2-SG` (Envia tráfego apenas para as instâncias) |
  | HTTPS | TCP      | 443  | `EC2-SG` (Se estiver configurado para HTTPS) |

---

##### 📌 Regras para `EC2-SG` (Instâncias do WordPress)
| Tipo      | Protocolo | Porta  | Origem |
|-----------|----------|--------|--------|
| HTTP      | TCP      | 80     | `ALB-SG` (Aceita tráfego apenas do Load Balancer) |
| NFS       | TCP      | 2049   | `EFS-SG` (Permite comunicação com o EFS) |
| MySQL/Aurora | TCP   | 3306   | `RDS-SG` (Acesso ao banco de dados) |

- **Outbound:** Permitir todo o tráfego de saída (`0.0.0.0/0`).

---

##### 📌 Regras para `RDS-SG` (Banco de Dados)
| Tipo      | Protocolo | Porta  | Origem |
|-----------|----------|--------|--------|
| MySQL/Aurora | TCP | 3306 | `EC2-SG` (Somente instâncias do WordPress podem acessar o banco) |

- **Outbound:**  
  | Tipo  | Protocolo | Porta | Destino |
  |-------|----------|------|---------|
  | MySQL/Aurora | TCP | 3306 | `EC2-SG` (Restringe saída apenas para as instâncias) |

---

##### 📌 Regras para `EFS-SG` (Sistema de Arquivos)
| Tipo      | Protocolo | Porta  | Origem |
|-----------|----------|--------|--------|
| NFS       | TCP      | 2049   | `EC2-SG` (Permite que as instâncias EC2 acessem o EFS) |

- **Outbound:** Permitir todo o tráfego de saída (`0.0.0.0/0`).

---

Agora, os **Security Groups estão configurados** e as regras de tráfego ajustadas para garantir a comunicação segura entre os serviços.  

### 4️⃣ Criando a AMI para as Instâncias EC2

A AMI (Amazon Machine Image) será usada para lançar as instâncias do WordPress. Para isso, primeiro criamos uma instância EC2, executamos um script de configuração e, depois, criamos a AMI.

---

#### 🔹 Criando a Imagem Base

1. No **AWS Console**, vá para **EC2 > Instances** e clique em **Launch Instance**.
2. Escolha a **imagem base**:
   - **Ubuntu Server 22.04 LTS** (ou a mais recente compatível)
3. Escolha o tipo de instância:
   - **t2.micro** (ou outro conforme necessidade)
4. Em **Key Pair**, escolha **nenhuma** (pois usaremos o Session Manager).
5. Em **Network Settings**, selecione:
   - **VPC**: `WordPressVPC`
   - **Subrede**: Qualquer **subnet pública disponível**
   - **Ative a opção "Auto-assign Public IP"** (A instância precisa de internet)
   - **Security Group**: `EC2-SG`
6. Em **IAM Role**, selecione a **Role criada anteriormente** com:
   - **SSM Managed Instance Core** (Para conexão via Session Manager)
   - **Amazon Elastic File System Full Access** (Para acessar o EFS)

7. Em **Advanced Details > User Data**, cole o `script_ami.sh`:

A instância leva alguns minutos para completar o download, então aguarde um tempo. Para checar a finalização conecte-se via Session manager use o comando:

 ``` bash
 cat /tmp/setup_done
 ```

8. Após a instância ser criada e o script ser finalizado com sucesso, selecione a instância na **console EC2**.
9. Clique em **Actions > Image and templates > Create Image**.
10. Forneça um nome para a imagem (ex: `wordpress-base-image`) e clique em **Create Image**.
11. Aguarde a Imagem ser criada, cheque isso na opção **AMIs** da barra lateral.
12. Após a imagem ser criada, ela estará disponível em **AMIs**. Agora, você pode usar essa imagem para criar novas instâncias EC2 baseadas nela.

### 5️⃣ Criando o Amazon EFS (Elastic File System)

O **Amazon EFS** será usado para armazenar arquivos estáticos do WordPress, permitindo que todas as instâncias EC2 compartilhem os mesmos dados.

---

#### 🔹 Criando o Sistema de Arquivos EFS

1. No **AWS Console**, vá para **Amazon EFS** e clique em **Create file system**.
2. Preencha os seguintes campos:
   - **Name**: `WordPressEFS`
   - **VPC**: `WordPressVPC`
3. Em **Availability and Durability**, selecione:
   - **Regional** (para garantir alta disponibilidade)

---

#### 🔹 Configurando as Subnets e Mount Targets

1. **Configurar Mount Targets** (Para que as instâncias consigam acessar o EFS):
   - **Adicione as duas subnets privadas** (onde as instâncias EC2 estarão rodando).
   - **Security Group**: Selecione `EFS-SG`.

2. Clique em **Next** e finalize a criação.

### 6️⃣ Criando o Amazon RDS para o Banco de Dados do WordPress

O **Amazon RDS** será utilizado para armazenar o banco de dados do WordPress de forma gerenciada, garantindo escalabilidade e segurança.

---

#### 🔹 Criando a Instância do Banco de Dados RDS

1. No **AWS Console**, vá para **Amazon RDS > Databases** e clique em **Create Database**.
2. Em **Database creation method**, selecione **Standard Create**.
3. Em **Engine options**, selecione:
   - **Engine type**: `MySQL`
   - **Edition**: `MySQL Community`
   - **Version**: Deixe a padrão.
4. Em **Templates**, selecione **Free Tier**.
5. Em **Settings**, configure:
   - **DB instance identifier**: `wordpress-db`
   - **Master username**: `admin`
   - **Master password**: Escolha uma senha segura e guarde para uso futuro.

---

#### 🔹 Configurando a Instância

1. Em **DB Instance Class**, escolha:
   - `db.t3.micro`.
2. Em **Storage**, selecione:
   - **Storage type**: `GP2 (General Purpose SSD)`
   - **Allocated storage**: `20 GiB` (máximo do Free Tier)
3. Em **Connectivity**:
   - **VPC**: `WordPressVPC`
   - **Subnet group**: Crie um novo grupo ou selecione um que cubra as **duas subnets privadas**.
   - **Public access**: ❌ **Desabilite** (o banco de dados só será acessado internamente).
   - **VPC security groups**: Selecione `RDS-SG`.

---

#### 🔹 Configurações Adicionais

1. Em **Database options**:
   - **Initial database name**: `wordpress`
2. Clique em **Create Database** e aguarde a criação.

---

### 7️⃣ Criando o Launch Template para as Instâncias EC2

Agora, vamos criar um **Launch Template** para facilitar a criação de novas instâncias EC2 no Auto Scaling Group, com a configuração necessária para executar o Docker e o WordPress.

#### 🔹 Criando o Launch Template

1. Acesse o **Console da AWS**, vá até o serviço **EC2** e clique em **Launch Templates**.
2. Clique em **Create Launch Template**.

#### 🔹 Configurações do Launch Template

Na criação do Launch Template, configure os seguintes parâmetros:

- **Launch Template Name**: `WordPress-LaunchTemplate`
- **Version Description**: `v1`
- **AMI**: Selecione a **AMI que você criou anteriormente**.
- **Instance Type**: Selecione o tipo de instância `t2.micro` (Free Tier).
- **Key Pair**: Não é necessário escolher um par de chaves, pois as instâncias EC2 serão gerenciadas pelo **Session Manager**.
- **Network Settings**: Não defina a VPC nem a Subnet agora, isso será configurado no Auto Scaling Group.
- **IAM Role**: Selecione a **Role criada anteriormente** com permissões para acesso ao Systems Manager e ao EFS.
- **User Data**: Insira o `script_template` para instalar o Docker, configurar o ambiente e iniciar o WordPress com Docker Compose.
- **Não se esqueça de substituir os dados do seu ambiente no script**, especificamente nas partes de configuração do Docker e de montagem do EFS. Abaixo estão as instruções detalhadas sobre onde encontrar os valores necessários:

1. **Configuração do Banco de Dados no Docker Compose**:
   No arquivo de configuração do Docker Compose, substitua os seguintes valores para conectar o WordPress ao seu banco de dados RDS:
   
   ```bash
   WORDPRESS_DB_HOST: {endpoint_do_RDS}  # Substitua pelo endpoint do seu banco de dados RDS
   WORDPRESS_DB_USER: admin             # O nome de usuário do banco de dados (foi configurado ao criar o RDS)
   WORDPRESS_DB_PASSWORD: {senha}       # A senha que você configurou ao criar o RDS
   WORDPRESS_DB_NAME: wordpress         # O nome do banco de dados (se você usou 'wordpress' ao criar o banco de dados RDS)
   
**Onde encontrar o endpoint_do_RDS**: O endpoint do seu banco de dados RDS pode ser encontrado no console do RDS, na seção Databases. Basta selecionar o banco de dados que você criou e, na página de detalhes, localizar o Endpoint.

2. **Montagem do EFS**:
   Para montar o EFS na instância EC2, substitua o ID do seu EFS no comando abaixo. O ID do EFS pode ser encontrado no console do EFS.

```bash
# Monta o EFS (substitua 'fs-XXXXXXXX' pelo ID do seu EFS)
sudo mount -t efs -o tls fs-XXXXXXXX:/ /mnt/efs
```

**Onde encontrar o ID do seu EFS**: O ID do seu EFS pode ser encontrado no console do EFS, na seção File Systems. Clique no sistema de arquivos EFS que você criou e, na página de detalhes, localize o File System ID.



  
### 8️⃣ Criando e Configurando o Classic Load Balancer (CLB)

O **Classic Load Balancer (CLB)** será responsável por distribuir o tráfego de entrada entre as instâncias EC2 que executam o WordPress. Para garantir a alta disponibilidade, o CLB será configurado nas duas subnets públicas e configurado para monitorar a saúde das instâncias através de um health check na URL `/healthcheck.php`.

#### 🔹 Criando o Classic Load Balancer

1. No **AWS Console**, vá para **EC2** e, no menu lateral, clique em **Load Balancers**.
2. Clique em **Create Load Balancer** e selecione a opção **Classic Load Balancer**.
3. Preencha os seguintes campos:
   - **Name**: `WordPress-CLB`
   - **Scheme**: `internet-facing` (O Load Balancer será acessível pela internet)
   - **Listener**: Deixe o protocolo como `HTTP` e a porta como `80`.

#### 🔹 Configurando as Subnets

1. Selecione as duas subnets públicas que você criou na VPC:
   - **PublicSubnet1**
   - **PublicSubnet2**

   Isso garantirá que o Classic Load Balancer esteja distribuído entre as duas zonas de disponibilidade.

#### 🔹 Configurando o Security Group

1. Para associar o Classic Load Balancer ao Security Group correto, selecione o **Security Group do Load Balancer** (`LB-SG`) que você criou anteriormente.
   - Esse Security Group permite tráfego HTTP (porta 80) de qualquer origem.

#### 🔹 Configurando o Health Check

1. Na seção de **Health Check**, configure os seguintes parâmetros:
   - **Ping Protocol**: `HTTP`
   - **Ping Port**: `80` (porta HTTP padrão)
   - **Ping Path**: `/healthcheck.php` (Arquivo PHP simples que você criará mais tarde para monitorar a saúde das instâncias EC2)
   O **health check** será usado para garantir que o CLB só envie tráfego para instâncias EC2 que estão funcionando corretamente.

#### 🔹 Finalizando a Criação do Load Balancer

1. Após a configuração do Health Check, passe para a próxima etapa, onde será possível revisar as configurações.
2. Clique em **Create** para criar o Classic Load Balancer.

### 9️⃣ Criando e Configurando o Auto Scaling Group (ASG)

Agora que o **Classic Load Balancer** foi criado e configurado, vamos configurar o **Auto Scaling Group (ASG)** para garantir que sempre existam **2 instâncias EC2** rodando, com escalabilidade automática conforme necessário. O ASG será responsável por gerenciar o número de instâncias EC2 e distribuí-las nas duas subnets privadas.

#### 🔹 Criando o Auto Scaling Group

1. No **AWS Console**, vá para **EC2 > Auto Scaling Groups**.
2. Clique em **Create Auto Scaling Group**.

#### 🔹 Configurando o Auto Scaling Group

1. **Escolha um Launch Template**:
   - Selecione o **Launch Template** que você criou anteriormente (`WordPress-LaunchTemplate`).

2. **Configurações do Auto Scaling Group**:
   - **Auto Scaling Group Name**: `WordPress-ASG`
   - **VPC**: Selecione a **VPC** que você criou (`WordPressVPC`).
   - **Subnets**: Selecione as **duas subnets privadas**:
     - `PrivateSubnet1`
     - `PrivateSubnet2`
   
3. **Configuração de Capacity**:
   - **Desired Capacity**: `2` (Número de instâncias desejado)
   - **Minimum Capacity**: `2` (Número mínimo de instâncias)
   - **Maximum Capacity**: `2` (Número máximo de instâncias)

4. **Load Balancer**:
   - Selecione o **Classic Load Balancer** que você criou anteriormente (`WordPress-CLB`).
   - Isso garantirá que o tráfego seja distribuído entre as instâncias EC2.

5. **Health Check**:
   - **Health Check Type**: Selecione **ELB** (Health Check do Load Balancer).
   - Isso permitirá que o Auto Scaling Group utilize o Health Check configurado no Load Balancer para verificar a saúde das instâncias.

6. **Configurações Adicionais**:
   - Deixe as configurações padrão para as **Políticas de Escalonamento** e **Notificações**.

7. **Revisar e Criar**:
   - Revise todas as configurações e, em seguida, clique em **Create Auto Scaling Group**.

Agora, o **Auto Scaling Group** foi configurado e irá garantir que haja sempre **2 instâncias EC2** ativas e distribuídas entre as subnets privadas. O ASG escalonará automaticamente as instâncias conforme a demanda, mantendo o número mínimo, desejado e máximo de instâncias em 2.
### 🔟 Finalização e Testes

Agora que a arquitetura está configurada, é hora de realizar os testes para garantir que tudo esteja funcionando corretamente.

#### 🔹 Testando o WordPress pelo Endereço de Domínio

1. **Acesse o Endereço de Domínio**:
   - Abra um navegador e digite o **DNS do Load Balancer**. Esse DNS pode ser encontrado no console da AWS, na seção **EC2 > Load Balancers**, e é o endereço gerado automaticamente pelo **Classic Load Balancer** (exemplo: `wordpress-lb-12345678.us-east-1.elb.amazonaws.com`).
   - A página inicial do **WordPress** deve ser carregada corretamente, indicando que as instâncias EC2 estão funcionando e o tráfego está sendo direcionado corretamente através do **Classic Load Balancer**.

2. **Testar a Funcionalidade do WordPress**:
   - Tente navegar pelas páginas do WordPress e, se possível, faça login na administração para garantir que tudo esteja operando normalmente.

#### 🔹 Testando a Conexão do EFS

Para verificar se o **Amazon EFS** está montado corretamente nas instâncias EC2, usaremos o **Session Manager** para acessar as instâncias sem a necessidade de SSH.

1. **Acessar a Instância via Session Manager**:
   - No **AWS Console**, vá para **Systems Manager > Session Manager**.
   - Clique em **Start session** e selecione a instância EC2 que faz parte do **Auto Scaling Group**.
   - Após a conexão ser estabelecida, você estará acessando a instância via terminal.

2. **Verificar a Montagem do EFS**:
   - No terminal, digite o seguinte comando para verificar se o EFS está montado corretamente:
     ```bash
     df -h
     ```
   - Procure pela pasta de montagem do EFS, que deve estar listada com o ponto de montagem correto (ex: `/mnt/efs`).
