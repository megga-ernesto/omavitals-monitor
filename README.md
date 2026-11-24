# ElMeGGa OmaVitals

![OmaVitals en Base, Cristal y Blur](preview.png)

*Paneles renderizados con datos de ejemplo y la paleta Rubí OLED. El desenfoque del fondo está simulado en la captura.*

Monitor de recursos para la barra de Omarchy. Muestra lecturas en vivo de CPU, RAM, zram, swap, GPU, disco, red, almacenamiento, batería y temperatura de CPU. Los sensores y datos de GPU disponibles dependen del equipo y sus controladores.

El panel muestra gráficas del último minuto, barras de porcentaje y detalles de hardware. La sección de procesos permite buscar por nombre, programa, ruta o PID, filtrar por actividad y agrupar por programa o proceso padre.

## Funciones

- Elige las métricas visibles y reordénalas con el tirador de cada medidor o con las flechas cuando tiene el foco.
- Configura la barra con iconos, texto o ambos. Ajusta los tamaños y el formato de cada lectura, como capacidad usada o restante, dirección del tráfico y grados Celsius o Fahrenheit.
- Consulta el último minuto de gráficas y el detalle de hardware. Elige las tarjetas por fila y un intervalo de muestreo de 1 a 30 segundos.
- Busca procesos, filtra por actividad, ordena por CPU, RAM, disco, antigüedad o nombre, y agrupa por programa o proceso padre. Puedes expandir los grupos y recorrer la lista por páginas.

## Requisitos

- Omarchy con el shell Quattro y soporte para complementos de barra
- Python 3 disponible como `python3`
- `lspci` es opcional y ayuda a identificar la GPU. En equipos NVIDIA, el monitor puede usar `nvidia-smi` si ya está disponible.

Las mediciones se recogen en el equipo. El monitor de procesos toma muestras mientras el panel está abierto. La interfaz está disponible en español e inglés.

## Instalación

Instala el complemento desde su repositorio público con el instalador de Omarchy.

```sh
omarchy plugin add https://github.com/megga-ernesto/omavitals-monitor.git --enable
```

Haz clic en el widget para abrir el panel. El engranaje despliega los ajustes de métricas, formatos de lectura, columnas y tamaños. El botón que está a su lado alterna entre las gráficas y la lista de procesos. Arrastra el tirador **⠿** de una tarjeta o pastilla para reordenar los medidores en el panel y en la barra.

El intervalo de muestreo predeterminado es de 2 segundos.

## Apariencia

Elige un acabado en **Ajustes → Apariencia**.

| Acabado | Apariencia |
|---|---|
| **Base** | Adopta el fondo, la transparencia y las reglas de composición de los paneles de Omarchy. |
| **Cristal** | Aplica un degradado traslúcido con 6 %, 3 % y 0 % de acento del tema, de arriba abajo. |
| **Blur** | Usa el mismo degradado y difumina el escritorio detrás del panel si Hyprland lo permite. |

Si Hyprland no puede aplicar Blur, el panel muestra Cristal y explica el motivo en Apariencia.

![Selector de apariencia y ajustes de medidores de OmaVitals](docs/appearance-settings.webp)

## Actualización y desinstalación

Las instalaciones hechas con `omarchy plugin add` se actualizan desde su repositorio Git con este comando.

```sh
omarchy plugin update elmegga.omavitals-monitor
```

Para quitar el complemento de la barra puedes deshabilitarlo. Para eliminar su copia local, usa el comando de desinstalación.

```sh
omarchy plugin disable elmegga.omavitals-monitor
omarchy plugin remove elmegga.omavitals-monitor
```

## Desarrollo

Desde la raíz del repositorio, valida el manifiesto antes de publicar cambios.

```sh
omarchy plugin validate .
```

## Licencia

[MIT](LICENSE).
