# Análisis Morfovolumétrico Cerebral Automatizado a partir de Imágenes T1-w

Este software implementa un pipeline completo para el procesamiento de estudios cerebrales estructurales (T1-w) de forma automatizada. Diseñado para operar dentro de contenedores Docker, el sistema garantiza máxima portabilidad y reproducibilidad en entornos clínicos y de investigación.

El núcleo del análisis integra herramientas estándar de neuroimagen (FreeSurfer y FSL) con algoritmos propios para generar segmentaciones precisas, métricas cuantitativas comparativas y reportes clínicos en formato PDF listos para su distribución.

## Referencia y Citación

La metodología y validación de este sistema se describen en la siguiente publicación. Si utiliza este software, por favor cite:

> **Fuentes, N., et al. (2023). Automated Structural Brain Analysis from T1-W Images. In: *VIII Latin American Conference on Biomedical Engineering and XLII National Conference on Biomedical Engineering*. IFMBE Proceedings, vol 86. Springer, Cham.**
> **DOI:** [https://doi.org/10.1007/978-3-032-06401-1_132](https://link.springer.com/chapter/10.1007/978-3-032-06401-1_132)

## Capacidades del Sistema

### Ingesta y Preprocesamiento

* **Detección Automatizada:** Monitoreo continuo de carpetas de entrada ("Hot-folder") con soporte nativo para archivos comprimidos (.zip) o directorios DICOM planos.
* **Gestión de Metadatos:** Extracción automática de edad, género y fecha del estudio directamente desde los encabezados DICOM para el enrutamiento del análisis.

### Procesamiento Morfométrico (Core)

* **Reconstrucción Cortical:** Ejecución optimizada del pipeline de FreeSurfer para la generación de modelos de superficie (White y Pial) y parcelación cortical (aparc+aseg).
* **Segmentación Volumétrica:** Cálculo preciso de volúmenes subcorticales, áreas de superficie, espesor cortical e índices de plegamiento (Gyrification Index).
* **Máscaras Macroestructurales:** Generación automática de segmentaciones para hemisferios, cerebelo, tronco encefálico y cuerpo calloso.

### Análisis Comparativo y Normativo

* **Base Normativa Dinámica:** Selección inteligente de un grupo control emparejado por edad y género específico para cada paciente.
* **Estadística Avanzada:** Cálculo de Z-scores e intervalos de confianza (99%) para todas las estructuras analizadas.
* **Análisis de Asimetría:** Evaluación cuantitativa de las diferencias interhemisféricas.

### Visualización y Reportes

* **Renderizado Headless:** Generación de capturas gráficas de mallas corticales y parcelaciones sin necesidad de interfaz gráfica física (Xvfb Smart Injection).
* **Salidas Cuantitativas:** Exportación de métricas completas en formato Excel (.xlsx).
* **Reporte Clínico PDF:** Compilación automática de un informe final que incluye:
* Heatmaps del perfil volumétrico comparado con controles.
* Gráficos personalizados de áreas, espesores y plegamiento.
* Visualización renderizada de la atrofia o preservación estructural.



## Arquitectura Técnica

El sistema está construido para entornos de alto rendimiento, soportando:

* **Paralelismo Nativo:** Orquestación de múltiples contenedores simultáneos con gestión de colas.
* **Gestión de Recursos:** Control de concurrencia y bloqueo de procesos (Smart Locking) para evitar colisiones de escritura.
* **Despliegue Contenerizado:** Totalmente encapsulado en Docker/LXC, eliminando conflictos de dependencias en el sistema host.
