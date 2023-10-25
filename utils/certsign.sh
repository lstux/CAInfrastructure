#!/bin/bash
SCRIPTFILE="$(realpath "${0}")"
WORKDIR="$(dirname "${SCRIPTFILE}")"

CADIR="${WORKDIR}"
OUTDIR=""
VALIDITY="730"

usage() {
  exec >&2
  [ -n "${1}" ] || printf "Error : %s\n" "${1}"
  printf "Usage : %s [options] req.csr [CAName]\n" "$(basename "${SCRIPTFILE}")"
  printf "  Sign certificate using provided certificate signing request file.\n"
  printf "  If CAName is omitted, a list of possible values will be displayed.\n"
  printf "Options :\n"
  printf "  -o outdir : output files to specified directory instead of same dir as csr\n"
  printf "  -e expire : set certificate to expire in expire days [${VALIDITY}]\n"
  printf "  -h        : display this help message\n"
  exit 1
}

while getopts o:e:h opt; do case "${opt}" in
  o) OUTDIR="${OPTARG}";;
  e) [ "${OPTARG}" -gt 0 ] || usage "certificate expire should be >0"; VALIDITY="${OPTARG}";;
  *) usage;;
esac; done
shift $((OPTIND - 1))
[ -e "${1}" ] || usage
CSRFILE="$(realpath "${1}")"
[ -n "${OUTDIR}" ] || OUTDIR="$(dirname "${CSRFILE}")"
CRTFILE="${OUTDIR}/$(basename "${CSRFILE}" .csr).crt"

if [ -n "${2}" ]; then
  [ -d "${CADIR}/${2}" ] || usage "CAName should match a directory in '${CADIR}'"
  CADIR="${CADIR}/${2}"
else
  calist=""
  for ca in "${CADIR}/"*; do
    [ -d "${ca}" ] || continue
    [ "${ca}" = "${CADIR}/RootCA" ] && continue
    calist="${calist} * $(basename "${ca}")\n"
  done
  [ -d "${CADIR}/RootCA" ] && calist="${calist} * RootCA\n"
  if [ -n "${calist}" ]; then
    printf "Available CAs to sign certificate :\n${calist}" >&2
    exit 1
  fi
  printf "Error, no CA infrastructure seems present in '%s'\n" "${CADIR}" >&2
  exit 2
fi

CACERT="${CADIR}/$(basename ${CADIR}).crt"
CAKEY="${CADIR}/$(basename ${CADIR}).key"
CAKEYPASS="${CADIR}/$(basename ${CADIR}).pass"

[ -e "${CACERT}" -a -e "${CAKEY}" ] || { printf "Error : no crt/key files in ${CADIR}...\n" >&2; exit 3; }
if [ -e "${CAKEYPASS}" ]; then
  openssl x509 -req -in "${CSRFILE}" -CA "${CACERT}" -CAkey "${CAKEY}" -passin "file:${CAKEYPASS}" -sha256 -days "${VALIDITY}" -out "${CRTFILE}"
else
  openssl x509 -req -in "${CSRFILE}" -CA "${CACERT}" -CAkey "${CAKEY}" -sha256 -days "${VALIDITY}" -out "${CRTFILE}"
fi
