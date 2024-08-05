#!/bin/bash

echo "============================================="
echo "Bienvenido al instalador del clúster PostgreSQL"
echo "Este proceso configurará un clúster PostgreSQL con Patroni y Consul."
echo "Se instalarán las versiones más recientes de todos los componentes."
echo "Script creado por: John Rivera González <johnriveragonzalez7@gmail.com>"
echo "============================================="
echo ""

# Obtener la IP local
NODE_IP=$(hostname -I | awk '{print $1}')
echo "La IP detectada para este nodo es: $NODE_IP"

# Verificar que la IP no esté vacía
if [ -z "$NODE_IP" ]; then
    echo "Error: no se pudo determinar la IP del nodo. Asegúrate de que el sistema está conectado a una red."
    exit 1
fi

# Solicitar la configuración del nodo antes de comenzar la instalación
echo "Determinando la configuración del nodo..."
read -p "¿Es este el nodo maestro (pg-001)? (s/n): " IS_MASTER

if [[ "$IS_MASTER" =~ ^[Ss]$ ]]; then
    NODE_NAME="pg-001"
    read -p "Ingrese la IP del nodo pg-002: " NODE_IP_2
    read -p "Ingrese la IP del nodo pg-003: " NODE_IP_3
    OTHER_NODES=("$NODE_IP_2" "$NODE_IP_3")
    # Generar contraseñas solo en el nodo maestro
    POSTGRES_PASSWORD=$(openssl rand -base64 12)
    REPL_PASSWORD=$(openssl rand -base64 12)
    echo "Guarde estas contraseñas para usarlas en la configuración de otros nodos:"
    echo "Contraseña de PostgreSQL: $POSTGRES_PASSWORD"
    echo "Contraseña de replicación: $REPL_PASSWORD"
else
    read -p "¿Es este el nodo pg-002? (s/n): " IS_PG002
    if [[ "$IS_PG002" =~ ^[Ss]$ ]]; then
        NODE_NAME="pg-002"
        read -p "Ingrese la IP del nodo maestro (pg-001): " NODE_IP_1
        read -p "Ingrese la IP del nodo pg-003: " NODE_IP_3
        OTHER_NODES=("$NODE_IP_1" "$NODE_IP_3")
    else
        NODE_NAME="pg-003"
        read -p "Ingrese la IP del nodo maestro (pg-001): " NODE_IP_1
        read -p "Ingrese la IP del nodo pg-002: " NODE_IP_2
        OTHER_NODES=("$NODE_IP_1" "$NODE_IP_2")
    fi
    echo "Ingrese las contraseñas proporcionadas por el administrador del nodo maestro:"
    read -p "Contraseña de PostgreSQL del nodo maestro: " POSTGRES_PASSWORD
    read -p "Contraseña de replicación: " REPL_PASSWORD
fi

echo "La configuración del nodo se ha completado."
echo ""

# Comenzar la instalación de paquetes y configuración
echo "Actualizando el sistema y preparando la instalación de componentes..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y wget curl gnupg2 lsb-release software-properties-common unzip python3 python3-pip

# Instalar psycopg para la conexión de Patroni con PostgreSQL
pip3 install psycopg

echo "Agregando el repositorio de PostgreSQL..."
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt update && sudo apt install -y postgresql

PG_VERSION=$(psql -V | awk '{print $3}' | cut -d. -f1)
echo "Versión de PostgreSQL detectada: $PG_VERSION"

# Inicializar la base de datos si el directorio de datos está vacío
if [ -z "$(ls -A /var/lib/postgresql/$PG_VERSION/main)" ]; then
    echo "Inicializando la base de datos PostgreSQL..."
    sudo -u postgres /usr/lib/postgresql/$PG_VERSION/bin/initdb -D /var/lib/postgresql/$PG_VERSION/main
    echo "Base de datos inicializada."
fi

# Establecer la contraseña para el usuario postgres
echo "Configurando la contraseña del usuario postgres..."
sudo -u postgres psql -c "ALTER USER postgres PASSWORD '$POSTGRES_PASSWORD';"

echo "Instalando Patroni..."
pip3 install patroni[consul]

# Obtener la última versión de Consul de la API de GitHub
CONSUL_VERSION=$(curl -s https://api.github.com/repos/hashicorp/consul/releases/latest | grep 'tag_name' | cut -d '"' -f 4 | sed 's/^v//')
echo "Descargando e instalando Consul versión $CONSUL_VERSION..."
wget https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip
unzip consul_${CONSUL_VERSION}_linux_amd64.zip
sudo mv consul /usr/local/bin/
rm consul_${CONSUL_VERSION}_linux_amd64.zip

# Configurar Consul como un servicio systemd
sudo useradd --system --home /etc/consul.d --shell /bin/false consul
sudo mkdir -p /etc/consul.d /var/lib/consul
sudo chown -R consul:consul /etc/consul.d /var/lib/consul

sudo tee /etc/consul.d/consul.hcl > /dev/null <<EOF
datacenter = "dc1"
data_dir = "/var/lib/consul"
client_addr = "0.0.0.0"
bind_addr = "$NODE_IP"
retry_join = ["${OTHER_NODES[@]}"]
ui = true
EOF

sudo tee /etc/systemd/system/consul.service > /dev/null <<EOF
[Unit]
Description=Consul
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target

[Service]
User=consul
Group=consul
ExecStart=/usr/local/bin/consul agent -server -bootstrap-expect=1 -data-dir=/var/lib/consul -config-dir=/etc/consul.d -bind=$NODE_IP
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable consul
sudo systemctl start consul

NUM_CPUS=$(grep -c ^processor /proc/cpuinfo)  # Obtiene el número de CPUs

echo "Configurando Patroni..."
PATRONI_CONFIG_FILE="/etc/patroni/${NODE_NAME}_patroni.yml"
sudo mkdir -p /etc/patroni
cat <<EOF | sudo tee $PATRONI_CONFIG_FILE
scope: postgres
namespace: /db/
name: $NODE_NAME
restapi:
  listen: 0.0.0.0:8008
  connect_address: $NODE_IP:8008
consul:
  host: 127.0.0.1:8500
bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        max_replication_slots: 5
        max_wal_senders: 5
        max_worker_processes: $NUM_CPUS
  initdb:
    - encoding: UTF8
    - data-checksums
  pg_hba:
    - host replication repl $NODE_IP/0 md5
    - host all all 0.0.0.0/0 md5
  users:
    admin:
      password: $POSTGRES_PASSWORD
postgresql:
  listen: 0.0.0.0:5432
  connect_address: $NODE_IP:5432
  data_dir: /var/lib/postgresql/$PG_VERSION/main
  bin_dir: /usr/lib/postgresql/$PG_VERSION/bin
  pgpass: /tmp/pgpass
  authentication:
    superuser:
      username: postgres
      password: $POSTGRES_PASSWORD
    replication:
      username: repl
      password: $REPL_PASSWORD
EOF

# Configurar Patroni como un servicio systemd
sudo tee /etc/systemd/system/patroni.service > /dev/null <<EOF
[Unit]
Description=Patroni
After=network.target

[Service]
User=postgres
Group=postgres
ExecStart=/usr/local/bin/patroni /etc/patroni/${NODE_NAME}_patroni.yml
Restart=always
LimitNOFILE=1024

[Install]
WantedBy=multi-user.target
EOF

sudo rm -rf /var/lib/postgresql/16/main/*
sudo -u postgres /usr/lib/postgresql/16/bin/initdb -D /var/lib/postgresql/16/main

sudo systemctl daemon-reload
sudo systemctl enable patroni
sudo systemctl start patroni


echo "Patroni configurado y en ejecución."
echo "Mostrando el estado del clúster de Patroni..."
patronictl -c $PATRONI_CONFIG_FILE list

if [[ "$IS_MASTER" =~ ^[Ss]$ ]]; then
    echo "Contraseñas para usar en la configuración de otros nodos:"
    echo "Contraseña de PostgreSQL: $POSTGRES_PASSWORD"
    echo "Contraseña de replicación: $REPL_PASSWORD"
fi

echo "Configuración completada."
