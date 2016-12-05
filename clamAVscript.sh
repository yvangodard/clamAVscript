#!/bin/bash
version="clamAVscript v 1.1 - 2016 - Yvan GODARD - godardyvan@gmail.com"
scriptDir=$(dirname $0)
scriptName=$(basename $0)
scriptNameWithoutExt=$(echo "${scriptName}" | cut -f1 -d '.')
system=$(uname -a)
logDir="/var/log/clamav"
logFile="${logDir%/}/clamav.log"
dirToScan="/var/www%/var/mail"
fileDirToScan=$(mktemp /tmp/${scriptNameWithoutExt}_fileDirToScan.XXXXX)
tmpLog=$(mktemp /tmp/${scriptNameWithoutExt}_tmpLog.XXXXX)
clamscanOutput=$(mktemp /tmp/${scriptNameWithoutExt}_clamscanOutput.XXXXX)
dirToExclude=""
specificDirToScan=0
githubRemoteScript="https://raw.githubusercontent.com/yvangodard/clamAVscript/master/clamAVscript.sh"
emailReport="nomail"
infected=0
error=0
help="no"
toBeUpdated=0

# Vérification du système pour choisir quelle commande MD5 sera utilisée
echo ${system} | grep "Darwin" > /dev/null 2>&1
if [[ $? -eq 0 ]]; then
	systemOs="Mac"
	function encode () {
		echo "${1}" | md5
	}
fi
echo ${system} | grep "Linux" > /dev/null 2>&1
if [[ $? -eq 0 ]]; then
	systemOs="Linux"
	function encode () {
		echo "${1}" | md5sum | awk '{print $1}'
	}
fi

# Check URL
function checkUrl () {
	command -p curl -Lsf "$1" >/dev/null
	echo "$?"
}

# Changement du séparateur par défaut et mise à jour auto
OLDIFS=$IFS
IFS=$'\n'
# Auto-update script, en fonction de l'OS
# On teste l'empreinte MD5 du script et on la compare à celle de GitHub
if [[ ${systemOs} == "Mac" ]] && [[ $(checkUrl ${githubRemoteScript}) -eq 0 ]] && [[ $(md5 -q "$0") != $(curl -Lsf ${githubRemoteScript} | md5 -q) ]]; then
	toBeUpdated=1
fi
if [[ ${systemOs} == "Linux" ]] && [[ $(checkUrl ${githubRemoteScript}) -eq 0 ]] && [[ $(md5sum "$0" | awk '{print $1}') != $(curl -Lsf ${githubRemoteScript} | md5sum | awk '{print $1}') ]]; then
	toBeUpdated=1
fi
# Si une mise à jour est à faire on la réalise
if [[ ${toBeUpdated} -eq "1" ]]; then
	[[ -e "$0".old ]] && rm "$0".old
	mv "$0" "$0".old
	curl -Lsf ${githubRemoteScript} >> "$0"
	if [ $? -eq 0 ]; then
		chmod +x "$0"
		exec ${0} "$@"
		exit $0
	else
		echo "Un problème a été rencontré pour mettre à jour ${0}."
		echo "Nous poursuivons avec l'ancienne version du script."
	fi
fi
IFS=$OLDIFS

function help () {
	echo "${version}"
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
	echo "./${scriptName} [-h] | [-e <email>]"                    
	echo "                  [-d <directories to scan>]"
	echo "                  [-L <log file>]"
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
	echo "                                  (par défaut : '${dirToScan}')"
	echo "     -L <log file> :              fichier où enregistrer les logs (par défaut : '${logFile}')"
	echo "     -l <email level> :           paramètre d'envoi du rapport par email,"
	echo "                                  doit être 'onerror', 'always' ou 'nomail',"
	echo "                                  (par défaut : '${emailReport}')"
	echo "     -E <excluded directories> :  répertoires à exclure du scan. Séparer les valeurs par un pipe '|',"
	echo "                                  et mettre des guillemets (par exemple : '\"/test|/home/user2\"')"
	exit 0
}

# Vérification des options/paramètres du script 
optsCount=0
while getopts "he:d:L:l:E:" OPTION
do
	case "$OPTION" in
		h)	help="yes"
						;;
		e)	emailAddress=${OPTARG}
						;;
	    d) 	[[ ! -z ${OPTARG} ]] && echo ${OPTARG} | perl -p -e 's/%/\n/g' | perl -p -e 's/ //g' | awk '!x[$0]++' >> ${fileDirToScan}
			specificDirToScan=1
						;;
	    L) 	logFile=${OPTARG}
			logDir=$(dirname ${logFile})
						;;
	    l) 	emailReport=${OPTARG}
						;;
	    E) 	dirToExclude=${OPTARG}
						;;
	esac
done

[[ ${help} = "yes" ]] && help

if [[ ! -d ${logDir%/} ]]; then
	mkdir -p ${logDir%/}
	[ $? -ne 0 ] && echo "Problème pour créer le dossier des logs '${logDir%/}'." && exit 1
fi

if [[ ! -f "${logFile}" ]]; then
	touch ${logFile}
	[ $? -ne 0 ] && echo "Problème pour accéder au fichier de logs '${logFile}'." && exit 1
fi

if [[ ! -d ${logFile%/} ]]; then
	mkdir -p ${logFile%/}
	[ $? -ne 0 ] && echo "Problème pour créer le sous-dossier des logs '${logFile%/}'." && exit 1
fi

# Redirect standard outpout to temp file
exec 6>&1
exec >> ${tmpLog}

echo "**** `date` ****"

# Contrôle du paramètre emailReport
if [[ ${emailReport} !== "always" ]] && [[ ${emailReport} !== "onerror" ]] && [[ ${emailReport} !== "nomail" ]]; then
	echo ""
	echo "Le paramètre '-E ${emailReport}' n'est pas correct. Nous poursuivons avec '-E nomail'."
	emailReport="nomail"
fi

# Contrôle du paramètre emailReport
if [[ ${emailReport} = "always" ]] || [[ ${emailReport} = "onerror" ]]; then
	# Test du contenu de l'adresse
	echo "${emailAddress}" | grep '^[a-zA-Z0-9._-]*@[a-zA-Z0-9._-]*\.[a-zA-Z0-9._-]*$' > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo ""
	    echo "Cette adresse '${emailAddress}' ne semble pas correcte."
	    echo "Nous continuons sans envoi d'email avec '- E nomail'."
	    emailReport="nomail"
	    emailAddress=""
	elif [[ -z ${emailAddress} ]]; then
		echo ""
		echo "L'adresse email est vide, nous continuons donc avec l'option '-l nomail'."
		emailReport="nomail"
	fi
fi

# Si il n'y a pas de dossier spécifique à scanner
[[ ${specificDirToScan} -eq "0" ]] && echo ${dirToScan} | perl -p -e 's/%/\n/g' | perl -p -e 's/ //g' | awk '!x[$0]++' >> ${fileDirToScan}

# Pour chaque dossier on fait un scan
for directory in $(cat ${fileDirToScan}); do
	hashDir=$(echo "${directory}" | encode)
	logThisDir=${logFile%/}/${hashDir}.log
	if [[ ! -f ${logThisDir} ]]; then
		touch ${logThisDir}
		[ $? -ne 0 ] && echo "Problème pour créer le fichier de log '${logThisDir}' concernant le dossier '${directory}'." && exit 1
	fi
	echo "" >> ${logThisDir}
	echo "-------------------------------" >> ${logThisDir}
	echo "$(date)" >> ${logThisDir}
	echo "Début du scan sur '${directory}'." >> ${logThisDir}
	echo "Logs séparés de ce dossier dans '${logThisDir}'." >> ${logThisDir}
	if [[ -e ${directory} ]]; then
		dirSize=$(du -sh "$directory" 2>/dev/null | cut -f1)
		echo "Volume à scanner : "$dirSize"."
		[[ -z ${dirToExclude} ]] && clamscan -ri --stdout "${directory}" >> ${logThisDir}
		[[ ! -z ${dirToExclude} ]] && clamscan -ri --stdout "${directory}" --exclude-dir="${dirToExclude}" >> ${logThisDir}
	elif [[ ! -e ${S} ]]; then
		let error=$error+1
		echo "Problème rencontré sur '${directory}', qui ne semble pas être correct." >> ${logThisDir}
	fi
	cat ${logThisDir} >> ${tmpLog}
done

# get the value of "Infected lines"
infected=$(tail ${tmpLog} | grep Infected | cut -d" " -f3)
[[ ${infected} -eq "0" ]] && echo "" && echo "*** Aucune infection détectée ***"
[[ ${infected} -ne "0" ]] && echo "" && echo "!!! INFECTION DÉTECTÉE !!!"
[[ ${error} -ne "0" ]] && echo "" && echo "*** Attention, une ou plusieurs erreurs rencontrées ***"

exec 1>&6 6>&-

if [[ ${emailReport} = "nomail" ]]; then
	cat ${tmpLog}
elif [[ ${emailReport} = "onerror" ]]; then
	if [[ ${infected} -ne "0" ]]; then
		cat ${tmpLog} | mail -s "[MALWARE : ${scriptName}] on $(hostname)" ${emailAddress}
	elif [[ ${error} -ne "0" ]]; then
		cat ${tmpLog} | mail -s "[error : ${scriptName}] on $(hostname)" ${emailAddress}
	fi
elif [[ ${emailReport} = "always" ]] ; then
	if [[ ${infected} -ne "0" ]]; then
		cat ${tmpLog} | mail -s "[MALWARE : ${scriptName}] on $(hostname)" ${emailAddress}
	elif [[ ${error} -ne "0" ]]; then
		cat ${tmpLog} | mail -s "[error : ${scriptName}] on $(hostname)" ${emailAddress}
	else
		cat ${tmpLog} | mail -s "[OK : ${scriptName}] on $(hostname)" ${emailAddress}
	fi
fi

cat ${tmpLog} >> ${logFile}

rm -R /tmp/${scriptNameWithoutExt}*

[[ ${error} -ne "0" ]] && exit 1
[[ ${infected} -ne "0" ]] && exit 2
exit 0