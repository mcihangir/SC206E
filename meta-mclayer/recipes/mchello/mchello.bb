SUMMARY = "Simple helloworld application"
SECTION = "examples"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://mchello.c"

S = "${WORKDIR}"

B = "${S}"

do_compile () {
	${CC} ${CFLAGS} ${LDFLAGS} mchello.c -o mchello
}

do_install () {
	install -d ${D}${bindir}
	install -m 0755 mchello ${D}${bindir}
}

FILES_${PN} = "${bindir}"