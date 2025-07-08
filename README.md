## Análisis Morfovolumétrico Automático a partir de Imágenes T1

Este software permite procesar estudios cerebrales estructurales (T1) de forma automatizada dentro de contenedores Docker para máxima portabilidad y compatibilidad. Está orientado al estudio de estructuras cerebrales mediante FreeSurfer y FSL, generando salidas gráficas, métricas cuantitativas y un informe final en PDF.

### Componentes del pipeline

- Preparación automática del estudio desde archivos `.zip` o carpetas con imágenes DICOM.
- Ejecución del pipeline de FreeSurfer para reconstrucción cortical.
- Generación de estadísticas morfométricas de volumen, área, índice de plegamiento y espesor cortical.
- Renderizado de la parcelación cortical (`aparc+aseg`) y estructuras anatómicas.
- Generación de máscaras macroestructurales: hemisferios, cerebelo, tronco encefálico y cuerpo calloso.
- Visualización de mallas corticales (superficies white y pial).
- Lectura automática de edad y género desde los metadatos DICOM.
- Selección dinámica de una base de datos control según edad y género del paciente.
- Cálculo de métricas volumétricas y análisis de asimetrías hemisféricas.
- Evaluación del grosor cortical regional.
- Análisis de áreas corticales.
- Cálculo de índices de plegamiento cortical.
- Exportación completa de resultados a archivos Excel.
- Generación de gráficos personalizados para cada métrica: áreas, espesores, plegamiento, parcelaciones, etc.
- Visualización tipo heatmap del perfil volumétrico comparado con controles.
- Generación automática de un informe morfométrico final en PDF.
