#!/bin/bash
SCRIPTFILE="$(realpath "${0}")"
WORKDIR="$(dirname "${SCRIPTFILE}")"
OUTDIR=""

RSA_FILE=""
RSA_PASSPHRASE=""
RSA_LENGTH="4096"
RSA_PASSLENGTH="128"
CRT_SUBJECT="C=FR/ST=Rhone/L=Lyon/O=LsLinux"

usage() {
  exec >&2
  printf "Usage : %s [options] domain [altdomain [...]]\n" "$(basename "${SCRIPTFILE}")"
  printf "Options :\n"
  printf "  -o outdir   : output files to specified directory instead of current/domain\n"
  printf "  -k rsa.key  : use specified RSA key instead of generating a new one\n"
  printf "  -p password : protect RSA key with password instead of generating one with pwgen\n"
  printf "  -K length   : generate length bits RSA keys [%s]\n" "${D_KEYLEN}"
  printf "  -P length   : protect RSA keys with lenth long passphrases [%s]\n" "${D_PASSLEN}"
  printf "  -h          : display this help message\n"
  exit 1
}

v3ext() {
  cat << EOF
[req]
req_extensions = v3_req

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
EOF
  local i n
  i=1; for n in "$@"; do
    echo "${n}" | grep -qE "^[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}\$" && continue
    i=$((i + 1))
    echo "DNS.${i} = ${n}"
  done
  i=0; for n in "$@"; do
    echo "${n}" | grep -qE "^[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}\$" || continue
    i=$((i + 1))
    echo "IP.${i} = ${n}"
  done
}

while getopts o:k:p:K:P:h opt; do case "${opt}" in
  o) OUTDIR="${OPTARG}";;
  k) [ -e "${OPTARG}" ] || usage "${OPTARG}, no such file\n"; RSA_FILE="${OPTARG}";;
  p) RSA_PASSPHRASE="${OPTARG}";;
  K) [ "${OPTARG}" -gt 0 ] 2>/dev/null || usage "keys length should be >0"; RSA_LENGTH="${OPTARG}";;
  P) [ "${OPTARG}" -gt 0 ] 2>/dev/null || usage "passpharses length should be >0"; RSA_PASSLENGTH="${OPTARG}";;
  *) usage;;
esac; done
shift $((OPTIND - 1))
[ -n "${1}" ] || usage

DOMAIN="${1}"
[ -n "${OUTDIR}" ] || OUTDIR="$(pwd)/${DOMAIN}"
shift
CSR_FILE="${OUTDIR}/${DOMAIN}.csr"
[ -e "${CSR_FILE}" ] && { printf "Error : ${CSR_FILE} already exists, remove first to proceed\n" >&2; exit 2; }
[ -e "${RSA_FILE}" ] || RSA_FILE="${OUTDIR}/${DOMAIN}.key"
V3EXT_FILE="${OUTDIR}/${DOMAIN}.v3.ext"
PASS_FILE="${OUTDIR}/${DOMAIN}.pass"

[ -d "${OUTDIR}" ] || install -d "${OUTDIR}" || exit 11
if ! [ -e "${RSA_FILE}" ]; then
  if [ -n "${RSA_PASSPHRASE}" ]; then echo "${RSA_PASSPHRASE}" > "${PASS_FILE}"; trap "rm -f ${PASS_FILE}" EXIT
  else pwgen -y "${RSA_PASSLENGTH}" 1 > "${PASS_FILE}"; fi || exit 12
  openssl genrsa -aes256 -passout "file:${PASS_FILE}" -out "${RSA_FILE}" "${RSA_LENGTH}" || exit 13
fi

if [ -n "${1}" ]; then
  v3ext "$@" > "${V3EXT_FILE}"
  openssl req -new -nodes -out "${CSR_FILE}" -key "${RSA_FILE}" -passin "file:${PASS_FILE}" -subj "/CN=${DOMAIN}/${CRT_SUBJECT}" -config "${V3EXT_FILE}" -extensions v3_req
else
  openssl req -new -nodes -out "${CSR_FILE}" -key "${RSA_FILE}" -passin "file:${PASS_FILE}" -subj "/CN=${DOMAIN}/${CRT_SUBJECT}"
fi || exit 14
