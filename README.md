
# zapping-bash

Cliente de zapping.com escrito para [GNU Bash](https://www.gnu.org/software/bash/).

![demo](./demo.gif)

## Licencia

Este proyecto es publicado utilizando la [licencia MIT](https://es.wikipedia.org/wiki/Licencia_MIT). Puedes ver detalles en el archivo [LICENSE](./LICENSE).

Este proyecto ha sido creado utilizando ingenería reversa. Los usuarios de este proyecto necesitarán una cuenta activa de Zapping para ver el contenido y el contenido sigue siendo propiedad de sus respectivos dueños.

Debido a que este no es un proyecto oficial, es posible que deje de funcionar en cualquier momento.

## Características

Este script soporta las siguientes características:

- Reproducción de canales en vivo
- Reproducción de contenido anterior
- HEVC (H.265)

## Plataformas

El script ha sido probado en GNU + Linux ([Manjaro](https://manjaro.org/)) y Mac OS para M1. Es posible que funcione en otras plataformas de todas formas, pero no tiene soporte oficial.

## Dependencias

Para funcionar, este script requiere:

- [mpv](https://mpv.io/)
- [jq](https://stedolan.github.io/jq/)
- [HTTPie](https://httpie.io/cli)
- [uuidgen](https://man7.org/linux/man-pages/man1/uuidgen.1.html)

Para instalar las dependencias en Arch o Manjaro, puedes ejecutar:

```bash
sudo pacman -S mpv jq httpie uuidgen util-linux
```

## Ejecutar

Corre el script desde el terminal:

```bash
./zapping.sh
```

La primera vez que se ejecute, el script generará un código para ser asociado a una cuenta como si fuera un televisor. Sigue las instrucciones en pantalla. El script guardará el token de Zapping en el archivo `$HOME/.config/zapping`.

## Parámetros

El script soporta los siguientes parámetros opcionales:

- `-h`: Muestra ayuda e información sobre parámetro
- `-v`: Habilita *verbose* que muestra detalles técnicos

Por ejemplo: `./zapping.sh -v`
