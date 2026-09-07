"""
Genera los diagramas de arquitectura del curso con iconografía oficial de AWS.

Por qué en código y no en draw.io: el diagrama queda versionado en git junto al
sistema que describe, se regenera con un comando y no se desincroniza en silencio
cuando la arquitectura cambia. El costo es no poder mover una caja a mano.

    python generar.py

Requiere:  pip install diagrams   +   Graphviz en el PATH (`dot`)
Salida:    ./salida/*.png
"""

from pathlib import Path

from diagrams import Cluster, Diagram, Edge, Node
from diagrams.aws.analytics import Athena, Glue, GlueCrawlers, GlueDataCatalog
from diagrams.aws.analytics import KinesisDataFirehose, KinesisDataStreams
from diagrams.aws.compute import EC2
from diagrams.aws.database import RDSPostgresqlInstance
from diagrams.aws.network import Endpoint, VPC
from diagrams.aws.security import IAMRole
from diagrams.aws.storage import S3
from diagrams.onprem.client import Users

SALIDA = Path(__file__).parent / "salida"
SALIDA.mkdir(exist_ok=True)

# Gris para lo que no es flujo de datos principal (permisos, red).
SECUNDARIO = Edge(color="darkgreen", style="dashed")

BASE = {"fontsize": "11", "pad": "0.4", "splines": "spline"}


def ruta(nombre: str) -> str:
    return str(SALIDA / nombre)


# =============================================================================
#  Sesión 3 — Nivel 1: vista de contexto
#  Qué se ve: quién usa el sistema y con qué se integra.
#  Qué NO se ve, a propósito: ningún servicio de AWS. A este nivel la pregunta
#  es "¿de quién es el problema?", no "¿con qué se implementa?".
# =============================================================================
def contexto():
    with Diagram(
        "Nivel 1 — Contexto: sistema de reservas de la aerolínea",
        filename=ruta("n1-contexto"),
        outformat="png",
        show=False,
        direction="LR",
        graph_attr=BASE,
    ):
        pasajero = Users("Pasajero")
        agencia = Users("Agencia de viajes")
        analista = Users("Analista comercial")

        with Cluster("Sistema de reservas"):
            reservas = Node("Reservas\n(OLTP)", shape="box", style="rounded,filled",
                            fillcolor="#e8f0fe")
            analitica = Node("Analítica\n(OLAP)", shape="box", style="rounded,filled",
                             fillcolor="#e8f0fe")

        pagos = Node("Proveedor de pagos\n(externo)", shape="box", style="rounded,dashed")

        pasajero >> Edge(label="busca y reserva") >> reservas
        agencia >> Edge(label="reserva por cupo") >> reservas
        reservas >> Edge(label="cobra") >> pagos
        pagos >> Edge(label="webhook de confirmación", style="dashed") >> reservas
        reservas >> Edge(label="ETL nocturno") >> analitica
        analitica >> Edge(label="consulta ocupación,\ningresos, cancelaciones") >> analista


# =============================================================================
#  Sesión 3 — Nivel 2: vista de componentes
#  Mismo sistema, un nivel más abajo: ahora sí, servicios concretos.
# =============================================================================
def componentes():
    with Diagram(
        "Nivel 2 — Componentes: implementación en AWS",
        filename=ruta("n2-componentes"),
        outformat="png",
        show=False,
        direction="LR",
        graph_attr=BASE,
    ):
        usuarios = Users("Pasajeros\ny agencias")

        with Cluster("VPC (us-east-1)"):
            api = EC2("API FastAPI")

            with Cluster("Bases de datos"):
                oltp = RDSPostgresqlInstance("RDS OLTP\naerolinea")
                olap = RDSPostgresqlInstance("RDS OLAP\naerolinea_dw")

            with Cluster("Catálogo y ETL"):
                crawler = GlueCrawlers("Crawler")
                catalogo = GlueDataCatalog("Data Catalog")
                job = Glue("Glue ETL Job")

            endpoint = Endpoint("VPC Endpoint S3\n(Gateway, gratis)")

        lago = S3("S3 — data lake\nraw / processed / curated")
        athena = Athena("Athena")
        rol = IAMRole("LabRole")

        usuarios >> api >> oltp
        oltp >> Edge(label="JDBC") >> crawler >> catalogo
        catalogo >> job
        oltp >> Edge(label="extrae") >> job
        job >> Edge(label="carga dimensiones\ny hechos") >> olap
        job >> Edge(label="escribe Parquet") >> lago
        lago >> athena
        job >> SECUNDARIO >> endpoint >> Edge(style="dashed") >> lago
        rol >> SECUNDARIO >> job


# =============================================================================
#  Sesión 4 — Alternativa A: ingesta batch
# =============================================================================
def alternativa_batch():
    with Diagram(
        "Alternativa A — Ingesta batch con Glue",
        filename=ruta("alt-a-batch"),
        outformat="png",
        show=False,
        direction="LR",
        graph_attr=BASE,
    ):
        oltp = RDSPostgresqlInstance("RDS OLTP")

        with Cluster("Ventana nocturna"):
            crawler = GlueCrawlers("Crawler")
            job = Glue("Glue ETL Job")

        lago = S3("S3 (Parquet,\nparticionado por fecha)")
        catalogo = GlueDataCatalog("Data Catalog")
        athena = Athena("Athena")

        oltp >> Edge(label="JDBC") >> crawler >> catalogo
        oltp >> Edge(label="extracción completa") >> job >> lago
        catalogo >> athena
        lago >> athena


# =============================================================================
#  Sesión 4 — Alternativa B: ingesta streaming
# =============================================================================
def alternativa_streaming():
    with Diagram(
        "Alternativa B — Ingesta streaming con Kinesis",
        filename=ruta("alt-b-streaming"),
        outformat="png",
        show=False,
        direction="LR",
        graph_attr=BASE,
    ):
        api = EC2("API FastAPI\n(emite eventos)")
        stream = KinesisDataStreams("Kinesis Data Streams")
        firehose = KinesisDataFirehose("Firehose\n(buffer + Parquet)")
        lago = S3("S3 (Parquet)")
        catalogo = GlueDataCatalog("Data Catalog")
        athena = Athena("Athena")

        api >> Edge(label="reserva creada,\npago confirmado") >> stream
        stream >> firehose >> lago
        catalogo >> athena
        lago >> athena


# =============================================================================
#  Checkpoint 1 — Data lake por zonas
# =============================================================================
def data_lake():
    with Diagram(
        "Checkpoint 1 — Data lake por zonas",
        filename=ruta("checkpoint-1-data-lake"),
        outformat="png",
        show=False,
        direction="LR",
        graph_attr=BASE,
    ):
        oltp = RDSPostgresqlInstance("RDS OLTP\n(fuente)")

        with Cluster("S3 — bucket del data lake"):
            raw = S3("raw/\nCSV crudo,\ninmutable")
            processed = S3("processed/\nParquet,\nparticionado")
            curated = S3("curated/\nmodelo estrella")

        with Cluster("Catálogo (Glue)"):
            crawler = GlueCrawlers("Crawler\n(on demand)")
            catalogo = GlueDataCatalog("Data Catalog")

        job = Glue("Glue ETL Job")
        athena = Athena("Athena")

        oltp >> Edge(label="extracción") >> raw
        raw >> Edge(label="limpieza\ny conversión") >> job >> processed
        processed >> Edge(label="modelado\ndimensional") >> curated
        processed >> crawler >> catalogo
        curated >> crawler
        catalogo >> athena
        curated >> athena


if __name__ == "__main__":
    for f in (contexto, componentes, alternativa_batch, alternativa_streaming, data_lake):
        f()
        print(f"[ok] {f.__name__}")
    print(f"\nDiagramas en: {SALIDA}")
