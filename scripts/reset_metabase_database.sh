#!/bin/bash
# Restauration de la dernière sauvegarde Metabase disponible dans le
# compartiment S3 vers la base de données dédiée à Metabase.
# À planifier quotidiennement, après la section Metabase de
# backup_database.sh.
# Ce script doit être lancé dans l'environnement de Scalingo car il
# utilise l'utilitaire `dbclient-fetcher` propre à la PaaS.
# Usage :
# ./restore_metabase_database.sh postgresql://user:password@host.name:port/database
# ou variable d'environnement DATABASE_URL.

# Lancement du script en mode strict (non officiel).
# http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -euo pipefail
IFS=$'\n\t'

mkdir -p ${BACKUPS_FOLDER_PATH}
script_folder_path=$(dirname "$0")
# L'URL de la base Metabase peut être fournie en argument ou par la
# variable d'environnement DATABASE_URL.
database_url=${1:-${DATABASE_URL:-}}

if [[ ! -n ${database_url} ]]; then
  echo "Il manque l'URL de la base de données Metabase. Fin du script."
  exit 0
fi

if [[ ! -n ${RCLONE_S3_ACCESS_KEY_ID} ]]; then
  echo "Ce script a besoin que Rclone soit correctement configuré."
  echo "Vérifiez que vous avez toutes les variables d'environnement requises."
  echo "Fin du script."
  exit 0
fi

# La version du client PG de Scalingo est la 14 or Supabase est en 15.
# Afin d'assurer une cohérence, il faut effectuer la mise à jour.
# Il n'y a pas d'autre moyen d'indiquer la version de PG.
# https://doc.scalingo.com/platform/databases/access
# Installé dans ${HOME}/bin.
dbclient-fetcher pgsql 15

if type rclone 2>/dev/null; then
  echo "Rclone est déjà installé."
else
  rclone_version='1.71.2'
  curl https://downloads.rclone.org/v${rclone_version}/rclone-v${rclone_version}-linux-amd64.zip -o rclone-v${rclone_version}-linux-amd64.zip
  # https://github.com/rclone/rclone/releases/download/v1.71.2/MD5SUMS
  if [[ $(echo "6238ac7cb4c9eb83f1b1f5077c931c22  rclone-v${rclone_version}-linux-amd64.zip" | md5sum --check) != "rclone-v${rclone_version}-linux-amd64.zip: OK" ]]; then
      echo '🙈 Le hash de rclone est différent de celui qui est attendu. Fin du script.'
      exit 0
  fi
  # -u met à jour le paquet dézippé s'il existe déjà.
  unzip -u rclone-v${rclone_version}-linux-amd64.zip
  mv "rclone-v${rclone_version}-linux-amd64/rclone" rclone
  chmod +x rclone
  export PATH="${PWD}:${PATH}"
fi

rclone_last_backup="$(rclone lsf --files-only --max-age 48h docurba_backups:/docurba-backups/metabase | sort --reverse --key 1 | head -n 1)"
if [[ ! -n "${rclone_last_backup}" ]]; then
  echo "Aucune sauvegarde Metabase récente trouvée dans le compartiment S3. Fin du script."
  exit 0
fi
rclone copy --max-age 48h "docurba_backups:/docurba-backups/metabase/${rclone_last_backup}" "${BACKUPS_FOLDER_PATH}"

files_count=$(ls -1 ${BACKUPS_FOLDER_PATH} | wc -l)
if [[ ${files_count} -gt 1 ]]; then
  echo "Plus d'un fichier de sauvegarde mais un seul est attendu."
  echo "Arrêt du script."
  exit 0
fi

backup_file="${BACKUPS_FOLDER_PATH}/$(ls ${BACKUPS_FOLDER_PATH} | head -1)"
echo "${backup_file} téléchargé correctement."


echo "Début de la restauration."

# pg_dump a été utilisé avec le format custom : le fichier peut être
# restauré directement avec pg_restore, sans décompression.
# sed is used here to :
# - insert DROP SCHEMA "docurba_private" then CREATE SCHEMA "docurba_private" commands first
# - replace "public" schema by "docurba_private"
# - replace "extensions"."uuid_generate_v4" by "gen_random_uuid"
pg_restore \
  --no-owner \
  --no-privileges \
  "${backup_file}" -f - |
sed \
  -e '1i DROP SCHEMA IF EXISTS "docurba_private" CASCADE; CREATE SCHEMA "docurba_private";' \
  -e 's/"public"\./"docurba_private"./g' \
  -e 's/"extensions"\."uuid_generate_v4"/"gen_random_uuid"/g' |
psql "${database_url}" &> /dev/null

echo "La restauration est terminée !"

echo "Début de l'anonymisation."
psql \
  --set ON_ERROR_STOP=1 \
  --file "${script_folder_path}/anonymize_metabase_database.sql" \
  --dbname "${database_url}"
echo "L'anonymisation' est terminée !"

echo "Début du changement de schema."
psql \
  --set ON_ERROR_STOP=1 \
  --dbname "${database_url}" <<EOF
DROP SCHEMA IF EXISTS docurba CASCADE;
ALTER SCHEMA docurba_private RENAME TO docurba;
GRANT USAGE ON SCHEMA docurba TO $DATABASE_READER_USER;
GRANT SELECT ON ALL TABLES IN SCHEMA docurba TO $DATABASE_READER_USER;
EOF
echo "Fin du changement de schema."

# Ne conservons pas une copie locale trop longtemps.
rm ${backup_file}
echo "Le fichier de sauvegarde est supprimé. Fin du script."

if [[ ! -n ${BACKUPS_SLACK_WEBHOOK} ]]; then
  echo "Le script est terminé mais Slack ne le saura pas car il manque la clé d'API."
  exit 0
fi

# https://docs.slack.dev/app-management/quickstart-app-settings#webhooks
curl -X POST -H 'Content-type: application/json'\
  --data '{"text":"😌 Restauration de la base de données Metabase effectuée avec succès."}'\
  ${BACKUPS_SLACK_WEBHOOK}

# Sans saut de ligne, ce message est collé au message précédent.
echo -e "\n"
echo "Fin du script."
