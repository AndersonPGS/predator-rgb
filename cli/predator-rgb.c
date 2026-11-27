// predator-rgb: controla o teclado RGB de 4 zonas do Acer Predator PH315-53 no macOS
// via kext PredatorWMI (ponte para o método WMI de gaming da Acer).
// Protocolo baseado no acer-wmi / facer (JafarAkhondali/acer-predator-turbo-and-rgb-keyboard-linux-module).
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>

#define SET_GAMING_LED 2
#define GET_GAMING_LED 4
#define GET_GAMING_SYS_INFO 5
#define SET_GAMING_STATIC_LED 6
#define SET_GAMINGKBBL 20
#define GET_GAMINGKBBL 21
#define CONF "/usr/local/etc/predator-rgb.conf"

static io_connect_t conn;

static int open_bridge(void) {
    io_service_t s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("PredatorWMIBridge"));
    if (!s) { fprintf(stderr, "kext PredatorWMI não carregado\n"); return -1; }
    kern_return_t kr = IOServiceOpen(s, mach_task_self(), 0, &conn);
    IOObjectRelease(s);
    if (kr) { fprintf(stderr, "falha ao abrir (0x%x). Rode com sudo.\n", kr); return -1; }
    return 0;
}

static int wmi(uint32_t method, const void *in, size_t len, uint64_t *out) {
    uint64_t sin = method, sout[3] = {0}; uint32_t n = 3;
    kern_return_t kr = IOConnectCallMethod(conn, 0, &sin, 1, in, len, sout, &n, NULL, NULL);
    if (kr || sout[2]) { fprintf(stderr, "WMI método %u falhou (kr=0x%x acpi=0x%llx)\n", method, kr, sout[2]); return -1; }
    if (out) *out = sout[0];
    return 0;
}

static void usage(void) {
    puts("uso:\n"
         "  predator-rgb info                         lê estado (somente leitura)\n"
         "  predator-rgb static R G B [zona 1-4|all] [brilho 0-100]\n"
         "  predator-rgb effect MODO [vel 1-9] [brilho] [dir 1|2] [R G B]\n"
         "     modos: 1 breath, 2 neon, 3 wave, 4 shifting, 5 zoom, 6 meteor, 7 twinkling\n"
         "  predator-rgb zones R,G,B R,G,B R,G,B R,G,B [brilho]   uma cor por zona\n"
         "  predator-rgb off\n"
         "  predator-rgb apply                        reaplica a última configuração salva\n"
         "a última configuração válida é salva em " CONF);
}

static int set_kbbl(int mode, int speed, int bright, int dir, int r, int g, int b) {
    uint8_t p[16] = {0};
    p[0] = mode; p[1] = speed; p[2] = bright; p[3] = (mode == 3) ? 8 : 0;
    p[4] = dir; p[5] = r; p[6] = g; p[7] = b; p[9] = 1;
    return wmi(SET_GAMINGKBBL, p, 16, NULL);
}

static int set_zone(int z, int r, int g, int b) {
    uint64_t v = 0; uint8_t *p = (uint8_t *)&v;
    p[0] = 1 << (z - 1); p[1] = r; p[2] = g; p[3] = b;
    return wmi(SET_GAMING_STATIC_LED, &v, 8, NULL);
}

static int run(int argc, char **argv) {
    const char *cmd = argv[1];
    if (!strcmp(cmd, "zones") && argc >= 6) {
        wmi(SET_GAMING_LED, &(uint64_t){8ULL | (15ULL << 40)}, 8, NULL);
        for (int z = 1; z <= 4; z++) {
            int r, g, b;
            if (sscanf(argv[1 + z], "%d,%d,%d", &r, &g, &b) != 3) { usage(); return 1; }
            if (set_zone(z, r, g, b)) return 1;
        }
        return set_kbbl(0, 0, argc >= 7 ? atoi(argv[6]) : 100, 0, 0, 0, 0) ? 1 : 0;
    }
    if (!strcmp(cmd, "info")) {
        uint64_t v, zero = 0;
        if (!wmi(GET_GAMING_SYS_INFO, &zero, 8, &v)) printf("sys_info:      0x%016llx\n", v);
        uint32_t in4 = 1;
        if (!wmi(GET_GAMINGKBBL, &in4, 4, &v)) printf("kbbl (get 21): 0x%016llx\n", v);
        uint64_t q = 1;
        if (!wmi(GET_GAMING_LED, &q, 8, &v)) printf("gaming_led:    0x%016llx\n", v);
        return 0;
    }
    if (!strcmp(cmd, "static") && argc >= 5) {
        int r = atoi(argv[2]), g = atoi(argv[3]), b = atoi(argv[4]);
        int bright = argc >= 7 ? atoi(argv[6]) : 100;
        int z0 = 1, z1 = 4;
        if (argc >= 6 && strcmp(argv[5], "all")) z0 = z1 = atoi(argv[5]);
        if (z0 < 1 || z1 > 4) { usage(); return 1; }
        // liga as 4 zonas (como o driver Linux faz na inicialização)
        wmi(SET_GAMING_LED, &(uint64_t){8ULL | (15ULL << 40)}, 8, NULL);
        for (int z = z0; z <= z1; z++)
            if (set_zone(z, r, g, b)) return 1;
        return set_kbbl(0, 0, bright, 0, 0, 0, 0) ? 1 : 0;
    }
    if (!strcmp(cmd, "effect") && argc >= 3) {
        int mode = atoi(argv[2]);
        int speed = argc > 3 ? atoi(argv[3]) : 4, bright = argc > 4 ? atoi(argv[4]) : 100;
        int dir = argc > 5 ? atoi(argv[5]) : 1;
        int r = argc > 8 ? atoi(argv[6]) : 0, g = argc > 8 ? atoi(argv[7]) : 0, b = argc > 8 ? atoi(argv[8]) : 0;
        if (mode < 1 || mode > 7) { usage(); return 1; }
        return set_kbbl(mode, speed, bright, dir, r, g, b) ? 1 : 0;
    }
    if (!strcmp(cmd, "off")) return set_kbbl(0, 0, 0, 0, 0, 0, 0) ? 1 : 0;
    usage();
    return 1;
}

int main(int argc, char **argv) {
    if (argc < 2) { usage(); return 1; }
    if (!strcmp(argv[1], "apply")) {
        FILE *f = fopen(CONF, "r");
        if (!f) { fprintf(stderr, "nada salvo em %s\n", CONF); return 1; }
        char line[512]; char *av[16]; int ac = 0;
        if (!fgets(line, sizeof line, f)) { fclose(f); return 1; }
        fclose(f);
        av[ac++] = argv[0];
        for (char *t = strtok(line, " \t\n"); t && ac < 15; t = strtok(NULL, " \t\n")) av[ac++] = t;
        av[ac] = NULL;
        if (ac < 2 || !strcmp(av[1], "apply") || !strcmp(av[1], "info")) return 1;
        // o EC pode ainda não estar pronto logo no boot: tenta algumas vezes
        for (int i = 0; i < 10; i++) { if (!open_bridge()) break; sleep(3); if (i == 9) return 1; }
        return run(ac, av);
    }
    if (open_bridge()) return 1;
    int rc = run(argc, argv);
    if (rc == 0 && strcmp(argv[1], "info")) {
        FILE *f = fopen(CONF, "w");
        if (f) { for (int i = 1; i < argc; i++) fprintf(f, "%s%s", argv[i], i + 1 < argc ? " " : "\n"); fclose(f); }
    }
    return rc;
}
