#!/bin/bash
# ------------------------------------------------------------------
# Autor: Victor Anderson <victor.anderson@esig.com.br>
# Nome: JBOSS INIT SCRIPT
# Data: 16/11/2015
# Atualizado: 29/08/2016
# ------------------------------------------------------------------

# --- Variáveis de ambiente
JBOSS_HOME=/opt/jboss # --- Define o caminho de instalação do JBOSS
EAR_SISTEMAS_HOME=/opt/sistemas # --- Define a raiz dos diretórios de EAR/Deploy
INSTANCES=($(ls $JBOSS_HOME/server/)) # --- Armazena as instâncias instaladas a partir de suas pastas
JBOSS_CONF=conf/java_opts.conf # --- Armazena o arquivo de configuração do JAVA a partir de $JBOSS_HOME/server/$INSTANCIA/
JBOSS_USER=sistemas # --- Define o usuário que executará e parará o Jboss
TENTATIVAS_DB=3 # --- Número de vezes que a função testa_db() vai tentar conectar com o banco
export JENKINS_HOME=/opt/.jenkins # --- Define a home do Jenkins caso exista na instância

export LANG="pt_BR.iso88591"
export LANGUAGE="pt_BR.iso88591:pt:en"

# --- Cores
NC='\033[0m'
RED='\033[0;31m'

# --- Função que checa a consistência e armazena todos os parâmetros necessários para as outras demais
function get_info(){
  export local INSTANCIA=$1 # --- Define a variável que vai escolher qual instância checar como primeiro argumento passado
  export local EAR_HOME
  export local DATABASE_SERVER
  export local DATABASE_PORT
  export local JAVA_OPTS
  export local STATUS
  export local DESABILITADA
  teste_inst "$INSTANCIA" # --- Testa se a instância existe
  LINHA=$(ps axf | grep "$INSTANCIA" | grep java | grep -v grep | awk '{print $1}') # --- Verifica se a instância já está sendo executada
  if [ -f "$JBOSS_HOME/server/$INSTANCIA/.inativa" ];then # --- Verifica se a instância está habilitada, caso não esteja, não faz outras checagens
    DESABILITADA=1
  else
    DESABILITADA=0
  fi
  if [ $DESABILITADA -eq 1 ];then # --- Verifica se a instância está habilitada, caso não esteja, não faz outras checagens
    :
  else
# --- Verifica diretório de EARs/Deploy
    if [ -d "$EAR_SISTEMAS_HOME/ear_$INSTANCIA" ]; then
      EAR_HOME="$EAR_SISTEMAS_HOME/ear_$INSTANCIA"
    else
      echo -e "O diretório de deploy da instância $INSTANCIA não existe ou está incorreto:"
      echo -e "$EAR_SISTEMAS_HOME/ear_$INSTANCIA${NC}"
      exit
    fi
# --- Verifica JAVA_OPTS
    if [ -f "$JBOSS_HOME/server/$INSTANCIA/$JBOSS_CONF" ]; then
      JAVA_OPTS=$(<"$JBOSS_HOME"/server/"$INSTANCIA"/"$JBOSS_CONF")
    else
      echo -e "O arquivo de configuração JAVA_OPTS não foi encontrado"
      echo -e "${RED}$JBOSS_HOME/server/$INSTANCIA/$JBOSS_CONF${NC}"
      exit
    fi
# --- Armazena o Datasource na variável DS para manipulação
    DATABASE_SERVER=$(grep '<xa-datasource-property name="ServerName"' "$EAR_HOME"/postgres-ds.xml | cut -d '>' -f 2 | cut -d '<' -f 1)
    DATABASE_SERVER=(${DATABASE_SERVER[@]}) # --- Joga todos os resultados em um array
    DATABASE_PORT=$(grep '<xa-datasource-property name="PortNumber"' "$EAR_HOME"/postgres-ds.xml | cut -d '>' -f 2 | cut -d '<' -f 1)
    DATABASE_PORT=(${DATABASE_PORT[@]}) # --- Joga todos os resultados em um array
    DATABASE_NAMES=$(grep DatabaseName "$EAR_HOME"/postgres-ds.xml | cut -f 2 -d '>' | cut -f 1 -d '<' | sort | uniq)
    DATABASE_NAMES=(${DATABASE_NAMES[@]})
  fi
}

# --- Mostra na tela informações básicas sobrea instância selecionada
function show_info(){
  echo -e "Instância ${RED}$INSTANCIA${NC} \n"
  echo "Servidor do Banco de Dados: ${DATABASE_SERVER[0]} : ${DATABASE_PORT[0]}"
  echo -e "Databases configuradas no ${RED}postgres-ds.xml${NC}:"
  for each in "${DATABASE_NAMES[@]}"; do
    echo "$each"
  done
  echo "Diretório de Deploy: ${EAR_HOME}"
  echo "Diretório do JBOSSs: $JBOSS_HOME"
  echo "Diretório de Trabalho: $JBOSS_HOME/server/$INSTANCIA"
  echo "$JAVA_OPTS"
  if [ "$LINHA" ]; then
    echo -e "\nStatus: ${RED}Iniciada${NC} sob o PID: ${RED}$LINHA${NC}."
  else
    echo -e "\nStatus: ${RED}Parada${NC}."
  fi
}

# --- Verifica se os diretórios da instância existem
function teste_inst() {
    if [ ! -d $JBOSS_HOME/server/"$INSTANCIA" ]; then
        echo -e "Instância ${RED}não${NC} encontrada!" 2>&1
        exit 1
    fi
}

# --- Testa conexão com o banco de dados da instância
function testa_DB() {
    local SUCESSO=0
    for _ in $(seq 1 $TENTATIVAS_DB); do
      CONNECT=$(curl --connect-timeout 1 "${DATABASE_SERVER[0]}":"${DATABASE_PORT[0]}" 2>&1 | grep "Empty")
      if [ "$CONNECT"  ]; then
            SUCESSO=1
            break
        fi
    done
    echo $SUCESSO
}

# --- Inicia a instância selecionada a partir da variável CMD_START
function start_inst() {
  # --- Comando a ser executado para iniciar o JBOSS
  cd $JBOSS_HOME  || exit
  export RUN_CONF=$JBOSS_HOME/server/$INSTANCIA/$JBOSS_CONF
  # --- Verifica se o arquivos de OPTS já possui o parâmetro de instanceName, caso não, nomeia de acorod com o diretório da instância
if grep -lq 'instanceName' "$RUN_CONF"; then
    local CMD_START="./bin/run.sh -b 0.0.0.0 -c $INSTANCIA > \
    $JBOSS_HOME/server/$INSTANCIA/log/console.log 2> \
    $JBOSS_HOME/server/$INSTANCIA/log/console.log &"
else
  local CMD_START="./bin/run.sh -b 0.0.0.0 -c $INSTANCIA -Dbr.ufrn.jboss.instanceName=$INSTANCIA > \
  $JBOSS_HOME/server/$INSTANCIA/log/console.log 2> \
  $JBOSS_HOME/server/$INSTANCIA/log/console.log &"
fi

# --- Checa se a instância está ativa
if [ $DESABILITADA -eq 1 ];then
    echo -e "A instância ${RED}$INSTANCIA${NC} está configurada como ${RED}INATIVA/DESABILITADA${NC} e não será iniciada"

else
  # --- Executa testa_DB para verificar se existe conectividade com o banco
  if [ "$LINHA" ]; then
    echo -e "A instância $INSTANCIA já está ativa sob o PID: ${RED}$LINHA${NC}"
  else
  # --- Executa testa_DB para verificar se existe conectividade com o banco
    if [ "$(testa_DB "$INSTANCIA")" -eq 1 ]; then
    # --- Checa se o usuário que está executando é o $JBOSS_USER, caso contrário executa "su $JBOSS_USER"
      if [[ "$USER" != "$JBOSS_USER" ]]; then
        echo "Você não é $JBOSS_USER. Executando com SU..."
        su -m "$JBOSS_USER" -c "$CMD_START" # --- -m mantem todas as variáveis de ambiente de root e as passa pra $JBOSS_USER
        echo -e "Instância ${RED}$INSTANCIA${NC} iniciada com sucesso!"
      else
        eval "${CMD_START}"
        echo -e "Instância ${RED}$INSTANCIA${NC} iniciada com sucesso!"
      fi
    else
        echo "Impossível conectar com o banco."
    fi
  fi
fi
}

# --- Para/mata a instância selecionada e limpa os diretórios temporários
function stop_inst() {
  if [ "$LINHA" ]; then
    echo "Matando processo.. $LINHA"
    while kill -0 $LINHA >/dev/null 2>&1
      do
        kill -9 "$LINHA"
      done
        limpar_work "$INSTANCIA"
        limpar_temp "$INSTANCIA"
        limpar_logs "$INSTANCIA"
  else
    echo -e "A instância ${RED}$INSTANCIA${NC} já está parada."
  fi
}

# --- Remove arquivos temporários do diretório WORK da instância
function limpar_work() {
    for file in "$JBOSS_HOME/server/$INSTANCIA/work"/*; do
        if [ -e "$file" ]; then
            echo -e "Removendo Work da Instância ${RED}$INSTANCIA${NC}"
            rm -rf $JBOSS_HOME/server/"$INSTANCIA"/work/*
            break
        fi
    done
}
# --- Remove arquivos temporários do diretório TMP da instância
function limpar_temp() {
    for file in "$JBOSS_HOME/server/$INSTANCIA/tmp"/*; do
        if [ -e "$file" ]; then
            echo -e "Removendo arquivos Temporários da Instância ${RED}$INSTANCIA${NC}"
            rm -rf $JBOSS_HOME/server/"$INSTANCIA"/tmp/*
            break
        fi
    done
}

# --- Remove todos os logs da instância que não sejam do dia atual
function limpar_logs() {
    for file in "$JBOSS_HOME/server/$INSTANCIA/log"/*.log.*; do
        if [ -e "$file" ]; then
            echo -e "Removendo Logs desnecessários da Instância ${RED}$INSTANCIA${NC}"
            rm -f "$JBOSS_HOME/server/$INSTANCIA/log"/*.log.*
            break
        fi
    done
}

# --- Mostra o status de determinada instância
function status(){
  if [ "$LINHA" ]; then
          echo -e "A instância $INSTANCIA se encontra: ${RED}INICIADA${NC}"
  else
    if [ $DESABILITADA -eq 1 ];then
          echo -e "A instância $INSTANCIA se encontra: ${RED}INATIVA/DESABILITADA${NC}"
    else
          echo -e "A instância $INSTANCIA se encontra: ${RED}PARADA${NC}"
    fi
  fi

}
function listar_instancias(){
  echo -e "Instâncias ${RED}disponíveis${NC}:"
  for each in "${INSTANCES[@]}"
do
  echo "$each"
done
}

function menu_instancias {
for INSTANCIA in "${INSTANCES[@]}"; do
  get_info "$INSTANCIA"
  status
done
echo "---------------------------------------------"
echo "----------------SIG INSTÂNCIAS---------------"
echo "---------------------------------------------"

  PS3="Digite a instância à dar manutenção: "
    select INSTANCIA in "${INSTANCES[@]}" "Todas" "Sair"; do
      case $INSTANCIA in
        Sair )
        echo "Saindo..."
        exit;;
        Todas )
        echo "1 - Iniciar todas as instâncias"
        echo "2 - Parar todas as instância"
        echo "3 - Reiniciar todas as instância"
        read -rp "Insira a função desejada: " OPT
          case $OPT in
            1) jboss -sa;;
            2) jboss -xa;;
            3) jboss -ra;;
          esac
        exit;;
        ${INSTANCES[REPLY-1]} )
        get_info "$INSTANCIA"
        echo "1 - Iniciar a instância"
        echo "2 - Parar a instância"
        echo "3 - Reiniciar a instância"
        echo "4 - Exibir informações sobre a instância"
        read -rp "Insira a função desejada: " OPT
          case $OPT in
            1) start_inst;;
            2) stop_inst;;
            3) stop_inst
               get_info "$INSTANCIA"
               echo "Reiniciando instância..."
               start_inst;;
            4) show_info;;
          esac
        exit
      esac
    done
}

# --- Verifica se o script foi executado sem parâmetros, caso sim, executa, caso não, abre o menu
if [ $# -eq 0 ]; then
    menu_instancias # --- Abre o menu se nenhum parâmetro foi passado
    exit 0
else {
# ------------------------------------------------------------------
#  Opções e parâmetros.
#
# -i ---- Mostra informações básicas da instância
# -r ---- Reiniciar instância
# -ra --- Reiniciar todas as instâncias
# -s ---- Iniciar instância
# -sa --- Iniciar todas instâncias
# -x ---- Parar instância
# -xa --- Parar todas as instâncias
# -l ---- Listar instâncias
# -c ---- Limpar arquivos temporários da instância (work, log)
# -t ---- Limpar todos temporários (temp, work, logs)
# ------------------------------------------------------------------
#while :; do
  case $1 in
    -m|--menu) menu_instancias
       ;;
    -r|--restart) get_info "$2"
       teste_inst "$2"
       stop_inst "$2"
       echo "Reiniciando instância..."
       get_info "$2"
       start_inst "$2"
       ;;
    -ra|--restart-all)
    for each in "${INSTANCES[@]}"; do
      get_info "$each"
      teste_inst "$each"
      stop_inst "$each"
      echo "Reiniciando instância..."
      get_info "$each"
      start_inst "$each"
    done
      ;;
    -s|--start) get_info "$2"
       teste_inst "$2"
       start_inst "$2"
       ;;
    -sa|--start-all)
    for each in "${INSTANCES[@]}"; do
      get_info "$each"
      teste_inst "$each"
      start_inst "$each"
    done
            ;;
    -x|--stop) get_info "$2"
       teste_inst "$2"
       stop_inst "$2"
       ;;
    -xa|--stop-all)
    for each in "${INSTANCES[@]}"; do
      get_info "$each"
      teste_inst "$each"
      stop_inst "$each"
    done
         ;;
    -l|--list) listar_instancias
       ;;
    -c|--clean) get_info "$2"
       teste_inst "$2"
       limpar_work "$2"
       limpar_logs "$2"
       ;;
    -t|--total-clean) get_info "$2"
       teste_inst "$2"
       limpar_temp "$2"
       limpar_work "$2"
       limpar_logs "$2"
       ;;
    -i|--info) get_info "$2"
       show_info "$2"
       ;;
    -h|*|--help)
cat <<EOF
Utilização: jboss -[opções] instancia

-h|--help           Esta informação
-i|--info           Mostra informações básicas da instância
-r|--restart        Reiniciar instância
-ra|--restart-all   Reinicia todas as instâncias
-s|--start          Iniciar instância
-x|--stop           Parar instância
-xa|--stop-all      Para todas as instâncias
-l|--list           Listar instâncias
-c|--clean          Limpar arquivos temporários da instância exceto logs (temp, work)
-t|--total-clean    Limpar todos temporários (temp, work, logs).
-m|--menu           Mostra o menu
EOF
       ;;
   esac
  shift
}
fi
