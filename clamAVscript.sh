#!/bin/bash
VERSION="clamAVscript v 1.0 - 2016 - Yvan GODARD - godardyvan@gmail.com"
SCRIPT_DIR=$(dirname $0)
SCRIPT_NAME=$(basename $0)
SCRIPT_NAME_WITHOUT_EXT=$(echo "${SCRIPT_NAME}" | cut -f1 -d '.')
LOGDIR="/var/log/clamav"
LOGFILE="${LOGDIR%/}/clamav-$(date +'%Y-%m-%d').log"
DIRTOSCAN="/var/www%/var/mail"
FILE_DIRTOSCAN=$(mktemp /tmp/${SCRIPT_NAME_WITHOUT_EXT}_FILE_DIRTOSCAN.XXXXX)
DIR_TO_EXCLUDE=""
SPECIFIC_DIR_TO_SCAN=0
githubRemoteScript="https://raw.githubusercontent.com/yvangodard/clamAVscript/master/clamAVscript.sh"
EMAIL_REPORT="nomail"
INFECTED=0
ERROR=0
HELP="no"

# Changement du séparateur par défaut et mise à jour auto
OLDIFS=$IFS
IFS=$'\n'
# Auto-update script
#if [[ $(checkUrl ${githubRemoteScript}) -eq 0 ]] && [[ $(md5 -q "$0") != $(curl -Lsf ${githubRemoteScript} | md5 -q) ]]; then
#	[[ -e "$0".old ]] && rm "$0".old
#	mv "$0" "$0".old
#	curl -Lsf ${githubRemoteScript} >> "$0"
#	if [ $? -eq 0 ]; then
#		chmod +x "$0"
#		exec ${0} "$@"
#		exit $0
#	else
#		echo "Un problème a été rencontré pour mettre à jour ${0}."
#		echo "Nous poursuivons avec l'ancienne version du script."
#	fi
#fi
IFS=$OLDIFS

help () {
	echo "${VERSION}"
	echo ""
	echo "Cet outil permet de réaliser un scan avec ClamAV de dossiers"
	echo "et d'être notifié par email en cas d'infection."
	echo ""
	echo "Avertissement :"
	echo ""
	echo "Cet outil est distribué dans support ou garantie,"
	echo "la responsabilité de l'auteur ne pourrait être engagée en cas de dommage causé à vos données."
	echo ""
	echo "Utilisation :"
	echo "./${SCRIPT_NAME} [-h] | [-e <email>]"                    
	echo "                  [-d <directories to scan>]"
	echo "                  [-D <log directory>]"
	echo "                  [-l <email level>]"
	echo "                  [-E <excluded directories>]"
	echo ""
	echo "     -h:                          affiche cette aide et quitte."
	echo ""
	echo "Paramètres optionnels :"
	echo "     -e <email> :                 email auquel sera envoyé le rapport (ex. : 'monnom@domaine.fr')."
	echo "                                  Obligatoire si '-l onerror' ou '-l always' est utilisé."
	echo "     -d <directories to scan> :   répertoire(s) à scanner. Séparer les valeurs par '%',"
	echo "                                  par exemple : '/var/mail%/home/test',"
	echo "                                  (par défaut : '${DIRTOSCAN}')"
	echo "     -D <log directory> :         dossier où stocker les logs (par défaut : '${LOGDIR}')"
	echo "     -l <email level> :           paramètre d'envoi du rapport par email,"
	echo "                                  doit être 'onerror', 'always' ou 'nomail',"
	echo "                                  (par défaut : '${EMAIL_REPORT}')"
	echo "     -E <excluded directories> :  répertoires à exclure du scan. Séparer les valeurs par un pipe '|',"
	echo "                                  (par exemple : '/test|/home/user2')"
	exit 0
}

# Vérification des options/paramètres du script 
optsCount=0
while getopts "he:d:D:l:E:" OPTION
do
	case "$OPTION" in
		h)	HELP="yes"
						;;
		e)	EMAIL_ADDRESS=${OPTARG}
						;;
	    d) 	[[ ! -z ${OPTARG} ]] && echo ${OPTARG} | perl -p -e 's/%/\n/g' | perl -p -e 's/ //g' | awk '!x[$0]++' >> ${FILE_DIRTOSCAN}
			SPECIFIC_DIR_TO_SCAN=1
						;;
	    D) 	LOGDIR=${OPTARG%/}
						;;
	    l) 	EMAIL_REPORT=${OPTARG}
						;;
	    E) 	DIR_TO_EXCLUDE=${OPTARG}
						;;
	esac
done

[[ ${HELP} = "yes" ]] && help

[[ -z ${EMAIL_ADDRESS} ]] && help

[ ! -e ${LOGDIR%/} ] && mkdir -p ${LOGDIR%/}
[ $? -ne 0 ] && echo "Problème pour créer le dossier des logs '${LOGDIR%/}'." && exit 1

# Redirect standard outpout to temp file
exec 6>&1
exec >> ${LOGFILE}

echo "**** `date` ****"

# Contrôle du paramètre EMAIL_REPORT
if [[ ${EMAIL_REPORT} != "always" ]] || [[ ${EMAIL_REPORT} != "onerror" ]] || [[ ${EMAIL_REPORT} != "nomail" ]]; then
	echo ""
	echo "Le paramètre '- E ${EMAIL_REPORT}' n'est pas correct. Nous poursuivons avec '- E always'."
	EMAIL_REPORT="always"
fi

# Contrôle du paramètre EMAIL_REPORT
if [[ ${EMAIL_REPORT} = "always" ]] || [[ ${EMAIL_REPORT} = "onerror" ]]; then
	# Test du contenu de l'adresse
	echo "${EMAIL_ADDRESS}" | grep '^[a-zA-Z0-9._-]*@[a-zA-Z0-9._-]*\.[a-zA-Z0-9._-]*$' > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo ""
	    echo "Cette adresse '${EMAIL_ADDRESS}' ne semble pas correcte."
	    echo "Nous continuons sans envoi d'email avec '- E nomail'."
	    EMAIL_REPORT="nomail"
	    EMAIL_ADDRESS=""
	elif [[ -z ${EMAIL_ADDRESS} ]]; then
		echo ""
		echo "L'adresse email est vide, nous continuons donc avec l'option '-l nomail'."
		EMAIL_REPORT="nomail"
	fi
fi

# Si il n'y a pas de dossier spécifique à scanner
[[ ${SPECIFIC_DIR_TO_SCAN} -eq 0 ]] && echo ${DIRTOSCAN} | perl -p -e 's/%/\n/g' | perl -p -e 's/ //g' | awk '!x[$0]++' >> ${FILE_DIRTOSCAN}

# Pour chaque dossier on fait un scan
for S in ${DIRTOSCAN}; do
	echo ""
	echo "Début du scan sur "$S"."
	if [[ -e ${S} ]]; then
		DIRSIZE=$(du -sh "$S" 2>/dev/null | cut -f1)
		echo "Volume à scanner : "$DIRSIZE"."
		[[ -z ${DIR_TO_EXCLUDE} ]] && clamscan -ri "$S"
		[[ ! -z ${DIR_TO_EXCLUDE} ]] && clamscn -ri "$S" --exclude-dir="${DIR_TO_EXCLUDE}"
	elif [[ ! -e ${S} ]]; then
		let ERROR=$ERROR+1
		echo "Problème rencontré sur : "$DIRSIZE", qui ne semble pas être correct."
	fi
done

# get the value of "Infected lines"
INFECTED=$(tail ${LOGFILE} | grep Infected | cut -d" " -f3)
[[ ${INFECTED} -eq "0" ]] && echo "" && echo "*** Aucune infection détectée ***"
[[ ${INFECTED} -ne "0" ]] && echo "" && echo "!!! INFECTION DÉTECTÉE !!!"
[[ ${ERROR} -ne "0" ]] && echo "" && echo "*** Attention, une ou plusieurs erreurs rencontrées ***"

exec 1>&6 6>&-

if [[ ${EMAIL_REPORT} = "nomail" ]]; then
	cat ${LOGFILE}
elif [[ ${EMAIL_REPORT} = "onerror" ]]; then
	if [[ ${INFECTED} -ne "0" ]]; then
		cat ${LOGFILE} | mail -s "[MALWARE : ${SCRIPT_NAME}] on $(hostname)" ${EMAIL_ADDRESS}
	elif [[ ${ERROR} -ne "0" ]]; then
		cat ${LOGFILE} | mail -s "[ERROR : ${SCRIPT_NAME}] on $(hostname)" ${EMAIL_ADDRESS}
	fi
elif [[ ${EMAIL_REPORT} = "always" ]] ; then
	if [[ ${INFECTED} -ne "0" ]]; then
		cat ${LOGFILE} | mail -s "[MALWARE : ${SCRIPT_NAME}] on $(hostname)" ${EMAIL_ADDRESS}
	elif [[ ${ERROR} -ne "0" ]]; then
		cat ${LOGFILE} | mail -s "[ERROR : ${SCRIPT_NAME}] on $(hostname)" ${EMAIL_ADDRESS}
	else
		cat ${LOGFILE} | mail -s "[OK : ${SCRIPT_NAME}] on $(hostname)" ${EMAIL_ADDRESS}
	fi
fi

[[ ${ERROR} -ne "0" ]] && exit 1
[[ ${INFECTED} -ne "0" ]] && exit 2
exit 0