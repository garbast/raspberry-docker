#!/bin/bash

DATABASE_PASSWORD=$2
readonly PROJECT_NAME=$1
readonly BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." > /dev/null 2>&1 && pwd )"

if [[ -z "${PROJECT_NAME}" ]]; then
  echo 'You must provide a project name'
  exit
fi

function create_project_folder() {
  local project_folder="${BASE_DIR}/Projects/${PROJECT_NAME}"

  if [[ ! -d ${project_folder} ]]; then
    mkdir -p "${project_folder}/public/"
    mkdir -p "${project_folder}/private/"
    mkdir -p "${project_folder}/shared/fileadmin"
    ln -s "${project_folder}/shared/fileadmin" "${project_folder}/private/fileadmin"

    echo "Project folder '${project_folder}' with subfolders created"
  else
    echo "Project folder '${project_folder}' with subfolders was previously created"
  fi
}

function create_apache_config() {
  local template_file="${BASE_DIR}/Setup/Apache/Config/vhosts/template"
  local destination_file="${BASE_DIR}/Setup/Apache/Config/vhosts/${PROJECT_NAME}.conf"

  if [[ ! -f ${destination_file} ]]; then
    cp ${template_file} ${destination_file}
    sed -i 's/\[project_name\]/'${PROJECT_NAME}'/' ${destination_file}

    echo "Apache configuration file '${destination_file}' created"
    docker exec -it amp_apache apachectl restart
  else
    echo "Apache configuration file '${destination_file}' was previously created"
  fi
}

function create_database() {
  if [[ -z "${DATABASE_PASSWORD}" ]]; then
    echo -n 'Enter the MariaDB root password to create a database for the project '
    read -s DATABASE_PASSWORD
    echo
  fi
  if [[ -z "${DATABASE_PASSWORD}" ]]; then
    echo 'No root password provided'
    exit
  fi

  local password=${DATABASE_PASSWORD}
  local db_name=${PROJECT_NAME//[.]/_}
  local db_exists=$(docker exec -it amp_mariadb mysqlshow -uroot -p${password} ${db_name} | grep '| Databases |' > /dev/null && echo 'not found')

  echo -n 'Please enter the PASSWORD of the new MySQL database! (example: t_dev) '
  read db_password
  echo

  if [[ ${db_exists} == 'not found' ]]; then
    docker exec -it amp_mariadb mysql -uroot -p${password} -e "CREATE DATABASE ${db_name} /*\!40100 DEFAULT CHARACTER SET utf8 */;"
    docker exec -it amp_mariadb mysql -uroot -p${password} -e "CREATE USER ${db_name}@localhost IDENTIFIED BY '${db_password}';"
    docker exec -it amp_mariadb mysql -uroot -p${password} -e "GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_name}'@'localhost';"
    docker exec -it amp_mariadb mysql -uroot -p${password} -e "FLUSH PRIVILEGES;"

    echo "Database '${db_name}' created and granted access to user '${db_name}' with password '${db_password}'"
  fi
}

function main() {
  create_project_folder
  create_apache_config
  create_database
}
main
