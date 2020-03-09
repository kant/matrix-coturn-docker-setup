#!/bin/bash

TEMPLATE_SED_FILEPATH="template.sed"

ERROR_CODE_NOT_ENOOUGH_ARGUMENTS=1
ERROR_CODE_SSL_DIRECTORIES_MISSING=2
ERROR_CODE_SSL_FILES_MISSING=3
ERROR_CODE_SSL_CANT_GENERATE_COMPLETE_PEM=4
ERROR_CODE_TEMPLATES_MISSING=5
ERROR_CODE_TEMPLATES_CANNOT_GENERATE_SED_FILE=6


bail_out() {
	error_code=$1
	#if [ -f "$TEMPLATE_SED_FILEPATH" ];
	#then
	#	rm "$TEMPLATE_SED_FILEPATH"
	#fi
	exit $error_code
}

generate_secret() {
	echo $(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
}

print_ssl_files_requirements() {
	echo "You need the following files :"
	echo "- fullchain.pem : Certificate with full chain of trust"
	echo "- privkey.pem   : The private key associated with the SSL certificate"
}

check_ssl_files_for() {
	domain=$1
	if [ ! -d "ssl/$domain" ];
	then
		echo "ssl/$domain is missing, or inaccessible"
		echo "Place the SSL files for $domain in ssl/$domain"
		print_ssl_files_requirements
		bail_out $ERROR_CODE_SSL_DIRECTORIES_MISSING
	fi

	if [ ! -f "ssl/$domain/fullchain.pem" -o ! -f "ssl/$domain/privkey.pem" ];
	then
		echo "Some files are missing in ssl/$domain"
		print_ssl_files_requirements
		bail_out $ERROR_CODE_SSL_FILES_MISSING
	fi

	echo "✓ SSL files are present"
}

complete_pem_is_present() {
	matrix_domain="$1"
	[ -f "ssl/$matrix_domain/complete.pem" ]
}

complete_pem_generate() {
	matrix_domain="$1"
	cat "ssl/$matrix_domain/fullchain.pem" "ssl/$matrix_domain/privkey.pem" > "ssl/$matrix_domain/complete.pem"
	if [ $? -ne 0 ];
	then
		echo "ssl/$domain/generate.pem is missing and its creation failed"
		echo "Could not do a simlpe "
		echo "cat fullchain.pem privkey.pem > complete.pem"
		echo "in ssl/$matrix_domain/"
		bail_out $ERROR_CODE_SSL_CANT_GENERATE_COMPLETE_PEM
	fi
}

template_generate_sed_file() {
	matrix_domain="$1"
	turn_domain="$2"
	synapse_server_name="$3"
	postgresql_password="$4"
	turn_username="$5"
	turn_password="$6"

	cat << EOF > "$TEMPLATE_SED_FILEPATH"
s/\${matrix_domain}/$matrix_domain/g
s/\${turn_domain}/$turn_domain/g
s/\${synapse_servername}/$synapse_server_name/g
s/\${postgresql_password}/$postgresql_password/g
s/\${turn_username}/$turn_username/g
s/\${turn_password}/$turn_password/g
EOF

	if [ $? -ne 0 ];
	then
		echo "Could not write into $TEMPLATE_SED_FILEPATH"
		echo "Exiting..."
		bail_out $ERROR_CODE_TEMPLATES_CANNOT_GENERATE_SED_FILE
	else
		echo "✓ sed file generated successfully"
	fi

	
}

template_check_for_files() {
	output_filepaths="$1"
	templates="present"

	for out_filepath in $output_filepaths;
	do
		template_filepath="$out_filepath.template"
		if [ ! -f "$template_filepath" ];
		then
			echo "Template for $template_filepath is not present anymore"
			templates="missing"
		fi
	done

	if [ ! "$templates" = "present" ];
	then
		echo "Some templates are missing"
		echo "Exiting"
		bail_out $ERROR_CODE_TEMPLATES_MISSING
	fi
}

template_generate_files() {
	output_filepaths="$1"
	for out_filepath in "$output_filepaths";
	do
		template_filepath="$out_filepath.template"
		sed -f "$TEMPLATE_SED_FILEPATH" "$template_filepath" > "$out_filepath"
	done
}

coturn_advise_to_add_user() {
	turn_username="$1"
	turn_password="$2"
	echo "The TURN credentials have been written in "
	echo "  synapse/conf/homeserver.d/voip.yaml"
	echo "Remember to add the TURN user in COTURN :"
	echo "docker exec coturn turnadmin -a -b \"/srv/coturn/turndb\" -u \"$turn_username\" -p \"$turn_password\" -r"
}

print_usage() {
	echo "./automate.sh your.matrix.domain.com your.turn.domain.com MatrixServerName"
	echo ""
	echo "Notes"
	echo "-----"
	echo ""
	echo "This script will (re)generate all the configuration files"
	echo "required to run an instance of Synapse, using this Docker"
	echo "setup."
	echo ""
	echo "A few things will be determined arbitrarily like :"
	echo "- The Postgresql password if POSTGRESQL_PASSWORD is not set"
	echo "  (Currently set to \"$POSTGRESQL_PASSWORD\")"
	echo "- The TURN username if TURN_USERNAME is not set"
	echo "  (Currently set to \"$TURN_USERNAME\")"
	echo "- The TURN password if TURN_PASSWORD is not set"
	echo "  (Currently set to \"$TURN_PASSWORD\")"
	echo ""
	echo "Each file will be generated using a filename.ext.template file"
	echo "Only the parts of the templates with \$\{ \} will be modified"
}

if [ "$#" -lt 3 ];
then
	echo "Not enough arguments"
	print_usage
	bail_out $ERROR_CODE_NOT_ENOOUGH_ARGUMENTS
fi

MATRIX_DOMAIN="$1"
TURN_DOMAIN="$2"
SYNAPSE_SERVER_NAME="$3"

# We don't check for strings with only spaces
# If the user REALLY want to fuck up his configuration
# I won't stop him

# Yes the comparator is "=" not "=="
# Because SHit happens

if [ "$POSTGRESQL_PASSWORD" = "" ];
then
	POSTGRESQL_PASSWORD="$(generate_secret)"
	echo "● PostgreSQL password not provided or empty"
	echo "● Generating a new password for PostgreSQL : $POSTGRESQL_PASSWORD"
fi

if [ "$TURN_USERNAME" = "" ];
then
	TURN_USERNAME="$(generate_secret)"
	echo "● TURN username not provided or empty"
	echo "● Generating a new TURN username : $TURN_USERNAME"
fi

if [ "$TURN_PASSWORD" = "" ];
then
	TURN_PASSWORD="$(generate_secret)"
	echo "● TURN password not provided or empty"
	echo "● Generating a new TURN password : $TURN_PASSWORD"
fi

echo "Using the following setup:"
echo "- MATRIX_DOMAIN       : $MATRIX_DOMAIN"
echo "- TURN_DOMAIN         : $TURN_DOMAIN"
echo "- SYNAPSE_SERVER_NAME : $SYNAPSE_SERVER_NAME"
echo "- POSTGRESQL_PASSWORD : $POSTGRESQL_PASSWORD"
echo "- TURN_USERNAME       : $TURN_USERNAME"
echo "- TURN_PASSWORD       : $TURN_PASSWORD"

template_generate_sed_file "$MATRIX_DOMAIN" "$TURN_DOMAIN" \
  "$SYNAPSE_SERVER_NAME" "$POSTGRESQL_PASSWORD" \
  "$TURN_USER" "$TURN_PASSWORD"

check_ssl_files_for "$MATRIX_DOMAIN"
check_ssl_files_for "$TURN_DOMAIN"

complete_pem_is_present "$MATRIX_DOMAIN" || complete_pem_generate "$MATRIX_DOMAIN"

echo "✓ ssl/$MATRIX_DOMAIN/complete.pem present"

FILES_TO_GENERATE="
coturn/conf/turnserver.conf
docker-compose.yml
env/postgres.env
haproxy/conf/haproxy.cfg
nginx/conf/nginx.conf
static/.well-known/matrix/server
"

template_check_for_files "$FILES_TO_GENERATE"

echo "✓ Template files present"

template_generate_files "$FILES_TO_GENERATE"

echo "✓ Configuration files generated !"

coturn_advise_to_add_user "$TURN_USERNAME" "$TURN_PASSWORD"
