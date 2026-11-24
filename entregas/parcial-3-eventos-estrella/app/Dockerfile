FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py eventos.py en_vivo.py estrella.py schema.sql ./
COPY sql ./sql
COPY static ./static
EXPOSE 8000
# Un solo proceso: los endpoints son síncronos y corren en el thread pool de FastAPI (40 hilos);
# la base limita la concurrencia real con el pool de 20 conexiones.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
