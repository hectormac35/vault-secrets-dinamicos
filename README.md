# 🔐 Vault – Gestión de Secretos Dinámicos (DevSecOps)

Proyecto **DevSecOps** que demuestra cómo gestionar **secretos de forma segura** utilizando **HashiCorp Vault**, evitando variables de entorno y secretos hardcodeados, y aplicando **credenciales dinámicas con rotación automática** para bases de datos.

---

## 🎯 Objetivo del proyecto

El objetivo de este proyecto es demostrar **buenas prácticas reales de seguridad en entornos DevOps**, mostrando cómo una aplicación puede:

- Autenticarse de forma segura contra Vault
- Obtener secretos **dinámicos y efímeros**
- Rotar credenciales automáticamente
- Evitar completamente el uso de `.env` o secretos en código
- Funcionar de forma transparente para la aplicación

Este enfoque es habitual en **entornos empresariales y cloud**, pero poco común en proyectos junior.

---

## 🧱 Arquitectura

La solución está compuesta por los siguientes elementos:

- **HashiCorp Vault**  
  Gestor centralizado de secretos.

- **Vault Agent**  
  Se encarga de la autenticación mediante AppRole y de inyectar los secretos en tiempo de ejecución.

- **PostgreSQL**  
  Base de datos con credenciales generadas dinámicamente por Vault.

- **FastAPI (Python)**  
  Aplicación backend que consume los secretos desde archivos, no desde variables de entorno.

- **Docker & Docker Compose**  
  Orquestación local de todos los servicios.

---

## 🔐 Flujo de seguridad

1. Vault se inicializa en modo desarrollo.
2. Se configura el **Database Secrets Engine** para PostgreSQL.
3. Se define un **AppRole** con permisos mínimos.
4. Vault genera **credenciales dinámicas** para la base de datos.
5. Vault Agent:
   - Se autentica usando AppRole
   - Obtiene un token temporal
   - Renderiza los secretos en un archivo compartido
6. La aplicación:
   - Lee las credenciales desde archivo
   - Se conecta a PostgreSQL
   - No conoce ni almacena secretos permanentes

---

## 🚫 Qué NO hace este proyecto (intencionadamente)

- ❌ No usa variables de entorno para secretos
- ❌ No guarda contraseñas en el código
- ❌ No utiliza `.env`
- ❌ No depende de secretos estáticos

---

## 🚀 Cómo levantar el proyecto (1 comando)

### Requisitos
- Docker
- Docker Compose

./levantar.sh
Este comando:

Levanta todos los contenedores

Configura Vault automáticamente

Genera credenciales dinámicas

Inicia la aplicación lista para usar

🌐 Endpoints disponibles

Una vez levantado el proyecto:

Estado de la app

GET http://localhost:8081/estado


Listar eventos (usa credenciales dinámicas)

GET http://localhost:8081/eventos


Crear evento

POST http://localhost:8081/eventos?mensaje=Hola_Vault

🔁 Rotación de secretos

Las credenciales de base de datos tienen un TTL corto

Vault genera automáticamente nuevas credenciales

Vault Agent actualiza los secretos sin reiniciar la app

La aplicación sigue funcionando sin cambios

📁 Estructura del proyecto
vault-secrets-dinamicos/
├── app/                # Aplicación FastAPI
├── vault/              # Configuración de Vault y Vault Agent
├── docker-compose.yml  # Orquestación de servicios
├── levantar.sh         # Script de arranque completo
├── README.md
└── .gitignore

🧠 Qué demuestra este proyecto

Conocimiento real de DevSecOps

Uso práctico de HashiCorp Vault

Principio de mínimo privilegio

Gestión segura de secretos

Automatización y reproducibilidad

Capacidad de depurar problemas reales de infraestructura
