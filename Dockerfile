# Custom PostgreSQL image for Kloud Kart
FROM postgres:18

# Label metadata
LABEL maintainer="Solution Architect"
LABEL description="Kloud Kart PostgreSQL 18 operational database instance"

# Default configuration:
# - max_connections=500: accommodates 400 concurrent buyer threads during flash-sale tests
# - shared_buffers=128MB: baseline memory setting tested in benchmarks
# - work_mem=4MB: standard per-operation memory setting
CMD ["postgres", "-c", "max_connections=500", "-c", "shared_buffers=128MB", "-c", "work_mem=4MB"]
