#!/bin/bash
SCRIPTFILE="$(realpath "${0}")"
WORKDIR="$(dirname "${SCRIPTFILE}")"
CONFFILE="${WORKDIR}/$(basename "${WORKDIR}").conf"
CA_ROOTDIR="$(dirname "${SCRIPTFILE}")"

#Default Values
D_CA_PREFIX="MyOrg"
D_CA_INTERMEDIATES="Prod Noprod"
D_KEYLEN="4096"
D_PASSLEN="128"
D_ROOT_VALIDITY="3650"
D_INTERMEDIATE_VALIDITY="1825"


D_COUNTRY="FR"
D_STATE="Rhone"
D_LOCALITY="Lyon"
D_ORGANIZATION="${D_CA_PREFIX}"
D_CA_SUBJECT="C=${D_COUNTRY}/ST=${D_STATE}/L=${D_LOCALITY}/O=${D_ORGANIZATION}"


usage() {
  exec >&2
  [ -n "${1}" ] && printf "Error : %s\n" "${1}"
  printf "Usage : %s [options]\n" "$(basename "${SCRIPTFILE}")"
  printf "  blahblah\n"
  printf "Options :\n"
  printf "  -c conf        : use specified conf file [%s]\n" "${CONFFILE}"
  printf "  -o outdir      : place generated files in outdir [this script dir]\n"
  printf "  -p prefix      : CA name prefix [%s]\n" "${D_CA_PREFIX}"
  printf "  -s subj        : set CA subject [${D_CA_SUBJECT}]\n"
  printf "  -i 'i1 i2 ...' : intermediate(s) CA(s) [%s]\n" "${D_CA_INTERMEDIATES}"
  printf "  -K length      : generate length bits RSA keys [%s]\n" "${D_KEYLEN}"
  printf "  -P length      : protect RSA keys with lenth long passphrases [%s]\n" "${D_PASSLEN}"
  printf "  -E expire      : root certificate expires in expire days [%s]\n" "${D_ROOT_VALIDITY}"
  printf "  -e expire      : intermediate certificates expire in expire days [%s]\n" "${D_INTERMEDIATE_VALIDITY}"
  printf "  -h             : display this help message\n"
  exit 1
}

getvar() {
  local varname="${1}" desc="${2}" regexp="${3:-}" default="${4:-}" a
  [ -n "${default}" ] || eval default=\"\$${varname}\"
  while true; do
    read -p "${desc} [${default}] : " a
    [ -z "${a}" -a -n "${default}" ] && { echo "${default}"; return 0; }
    if [ -n "${regexp}" ]; then
      echo "${a}" | grep -qE "${regexp}" && { echo "${a}"; return 0; }
      printf "${varname} should match regexp '${regexp}'\n" >&2
    else
      echo "${a}"
      return 0
    fi
  done
}

while getopts c:o:p:s:i:K:P:E:e:h opt; do case "${opt}" in
  c) [ -e "${OPTARG}" ] || usage "${OPTARG}, no such file\n"; CONFFILE="${OPTARG}";;
  o) CA_ROOTDIR="${OPTARG}";;
  p) CA_PREFIX="${OPTARG}";;
  s) CA_SUBJECT="${OPTARG}";;
  i) CA_INTERMEDIATES="${OPTARG}";;
  K) [ "${OPTARG}" -gt 0 ] 2>/dev/null || usage "keys length should be >0"; KEYLEN="${OPTARG}";;
  P) [ "${OPTARG}" -gt 0 ] 2>/dev/null || usage "passpharses length should be >0"; PASSLEN="${OPTARG}";;
  E) [ "${OPTARG}" -gt 0 ] 2>/dev/null || usage "root CA expire should be >0"; ROOT_VALIDITY="${OPTARG}";;
  e) [ "${OPTARG}" -gt "${ROOT_VALIDITY}" ] 2>/dev/null || usage "intermediates CA expire should be >rootCA expire"; INTERMEDIATE_VALIDITY="${OPTARG}";;
  *) usage;;
esac; done
shift $((OPTIND - 1))


if [ -e "${CONFFILE}" ]; then . "${CONFFILE}"
else printf "Warning : ${CONFFILE}, no such file\n" >&2; fi

[ -n "${CA_PREFIX}" ] || CA_PREFIX="$(getvar CA_PREFIX "Enter CA prefix (eg: your company name)" "^.+" "${D_CA_PREFIX}")"
[ -n "${CA_INTERMEDIATES}" ] || CA_INTERMEDIATES="$(getvar CA_INTERMEDIATES "Enter intermediate CA(s) name(s) (eg : your service)" "^.+" "${D_CA_INTERMEDIATES}")"
if ! [ -n "${CA_SUBJECT}" ]; then
  COUNTRY="$(getvar COUNTRY "Enter 2 letter country code" "^[A-Z]{2}" "${D_COUNTRY}")"
  STATE="$(getvar STATE "Enter state name" "^[A-Za-z0-9_-]+\$" "${D_STATE}")"
  LOCALITY="$(getvar LOCALITY "Enter city name" "^[A-Za-z0-9_-]+\$" "${D_LOCALITY}")"
  D_CA_SUBJECT="C=${COUNTRY}/ST=${STATE}/L=${LOCALITY}/O=${CA_PREFIX}"
fi
[ "${KEYLEN}" -gt 0 ] 2>/dev/null || KEYLEN="$(getvar KEYLEN "Enter RSA keys length in bits" "^[0-9]+\$" "${D_KEYLEN}")"
[ "${PASSLEN}" -gt 0 ] 2>/dev/null || PASSLEN="$(getvar PASSLEN "Enter RSA keys passphrase length" "^[0-9]+\$" "${D_PASSLEN}")"
[ "${ROOT_VALIDITY}" -gt 0 ] 2>/dev/null || ROOT_VALIDITY="$(getvar ROOT_VALIDITY "Enter Root CA validity in days" "^[0-9]+\$" "${D_ROOT_VALIDITY}")"
[ "${INTERMEDIATE_VALIDITY}" -gt 0 ] 2>/dev/null || INTERMEDIATE_VALIDITY="$(getvar INTERMEDIATE_VALIDITY "Enter intermediate CAs validity in days" "^[0-9]+\$" "${D_INTERMEDIATE_VALIDITY}")"
[ -e "${CONFFILE}" ] || sed -e "s@^#\? CA_ROOTDIR=.*@CA_ROOTDIR=\"${CA_ROOTDIR}\"@" \
                            -e "s@^CA_PREFIX=.*@CA_PREFIX=\"${CA_PREFIX}\"@" \
                            -e "s@^CA_INTERMEDIATES=.*@CA_INTERMEDIATES=\"${CA_INTERMEDIATES}\"@" \
                            -e "s@^KEYLEN=.*@KEYLEN=\"${KEYLEN}\"@" -e "s@^PASSLEN=.*@PASSLEN=\"${PASSLEN}\"@" \
                            -e "s@^ROOT_VALIDITY=.*@ROOT_VALIDITY=\"${ROOT_VALIDITY}\"@" \
                            -e "s@^INTERMEDIATE_VALIDITY=.*@INTERMEDIATE_VALIDITY=\"${INTERMEDIATE_VALIDITY}\"@" \
                        "${WORKDIR}/$(basename "${WORKDIR}").example.conf" > "${CONFFILE}"
exit 0

umask 0027
[ -d "${CA_ROOTDIR}" ] || install -d "${CA_ROOTDIR}" || exit 2

# Build Root CA
CADIR="${CA_ROOTDIR}/${CA_PREFIX}RootCA"
CAFILE="${CADIR}/${CA_PREFIX}RootCA"
[ -d "${CADIR}" ] || install -d -m750 "${CADIR}" || exit 11
[ -e "${CAFILE}.pass" ] || pwgen -y "${PASSLEN}" 1 > "${CAFILE}.pass" || exit 12
if [ -e "${CAFILE}.key" ]; then printf "Warning : '%s' already exist\n" "${CAFILE}.key" >&2
else openssl genrsa -aes256 -passout "file:${CAFILE}.pass" -out "${CAFILE}.key" "${KEYLEN}" || exit 13; fi
printf "Root CA RSA key generated : %s\n" "${CAFILE}.key"
if [ -e "${CAFILE}.crt" ]; then printf "Warning : '%s' already exist\n" "${cafile}.crt" >&2
else openssl req -x509 -new -nodes -key "${CAFILE}.key" -passin "file:${CAFILE}.pass" -sha256 -days "${ROOT_VALIDITY}" -out "${CAFILE}.crt" -subj "/CN=${CA_PREFIX} Root CA/${CA_SUBJECT}" || exit 14; fi
printf "Root CA certificate : %s\n" "${CAFILE}.crt"

# Build intermediate CAs
c=20
for i in ${CA_INTERMEDIATES}; do
  d="${CA_ROOTDIR}/${CA_PREFIX}${i}CA"
  f="${d}/${CA_PREFIX}${i}CA"
  [ -d "${d}" ] || install -d "${d}" || exit $((c + 1))
  [ -e "${f}.pass" ] || pwgen -y "${PASSLEN}" 1 > "${f}.pass" || exit $((c + 2))
  if [ -e "${f}.key" ]; then printf "Warning : '%s' already exist\n" "${f}.key" >&2
  else openssl genrsa -aes256 -passout "file:${f}.pass" -out "${f}.key" "${KEYLEN}" || exit $((c + 3)); fi
  if [ -e "${f}.csr" ]; then printf "Warning : '%s' already exist\n" "${f}.csr" >&2
  else openssl req -new -nodes -out "${f}.csr" -key "${f}.key" -passin "file:${f}.pass" -subj "/CN=${CA_PREFIX} ${i} CA/${CA_SUBJECT}" || exit $((c + 4)); fi
  if [ -e "${f}.crt" ]; then printf "Warning : '%s' already exist\n" "${f}.csr" >&2
  else openssl x509 -req -in "${f}.csr" -CA "${CAFILE}.crt" -CAkey "${CAFILE}.key" -passin "file:${CAFILE}.pass" -CAcreateserial -sha256 -days "${INTERMEDIATE_VALIDITY}" -out "${f}.crt" || exit $((c + 5)); fi
  c=$((c + 10))
done
[ -w "/etc/ssl/certs" ] && ln -s "${CAFILE}.crt" "/etc/ssl/certs/$(basename "${CAFILE}.crt")"

[ -e "${CA_ROOTDIR}/$(basename "${CONFFILE}")" ] || install -m 640 "${CONFFILE}" "${CA_ROOTDIR}/$(basename "${CONFFILE}")"
[ -e "${CA_ROOTDIR}/certsign.sh" ] || install -m 750 "${WORKDIR}/utils/certsign.sh" "${CA_ROOTDIR}/certsign.sh"
[ -d "${CA_ROOTDIR}/requests" ] || install -d "${CA_ROOTDIR}/requests"
[ -e "${CA_ROOTDIR}/requests/certrequest.sh" ] || install -m 750 "${WORKDIR}/utils/certrequest.sh" "${CA_ROOTDIR}/requests/certrequest.sh"
