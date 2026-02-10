# Yosh + Cal.com Setup Guide

## Part 1: Install Yosh

1. Copy `yosh-debian12-x86_64.tar.gz` and `install-yosh.sh` to the server.

2. Run the installer:
   ```bash
   sudo ./install-yosh.sh
   ```

3. Create your API key file:
   ```bash
   echo 'sk-ant-YOUR-KEY-HERE' > ~/.yoshkey
   chmod 600 ~/.yoshkey
   ```

4. Start yosh:
   ```bash
   yosh
   ```

5. Optionally set as default shell:
   ```bash
   sudo chsh -s /usr/local/bin/yosh cyberian
   ```

## Part 2: Set Up Cal.com

### Clone and configure

1. Clone the repo:
   ```bash
   git clone https://github.com/calcom/cal.com.git
   cd cal.com
   ```

2. Copy the example env:
   ```bash
   cp .env.example .env
   ```

3. Set the database URLs (match credentials from docker-compose.yml):
   ```bash
   sed -i 's|DATABASE_URL="postgresql://postgres:@localhost:5450/calendso"|DATABASE_URL="postgresql://unicorn_user:magical_password@database:5432/calendso"|' .env
   sed -i 's|DATABASE_DIRECT_URL="postgresql://postgres:@localhost:5450/calendso"|DATABASE_DIRECT_URL="postgresql://unicorn_user:magical_password@database:5432/calendso"|' .env
   ```

4. Generate secrets and set them in .env:
   ```bash
   openssl rand -base64 32
   # paste output as NEXTAUTH_SECRET in .env

   openssl rand -base64 24
   # paste output as CALENDSO_ENCRYPTION_KEY in .env
   ```

5. Set NEXTAUTH_URL to your server's IP:
   ```bash
   sed -i "s|NEXTAUTH_URL='http://localhost:3000'|NEXTAUTH_URL='http://YOUR-SERVER-IP:3000'|" .env
   ```

6. Add docker-compose variables to .env:
   ```bash
   cat >> .env << 'EOF'
   POSTGRES_USER=unicorn_user
   POSTGRES_PASSWORD=magical_password
   POSTGRES_DB=calendso
   DATABASE_HOST=database
   REDIS_URL=redis://redis:6379
   EOF
   ```

### Disable local builds (use pre-built images)

This avoids the memory-heavy yarn install step.

7. Comment out the build blocks in docker-compose.yml:
   ```bash
   sed -i '39,55s/^/#/' docker-compose.yml
   ```

8. Comment out the calcom-api build block and add the pre-built image.
   Find the `calcom-api` service and replace:
   ```yaml
       build:
         context: .
         dockerfile: apps/api/v2/Dockerfile
         args:
           DATABASE_URL: ${DATABASE_URL}
           DATABASE_DIRECT_URL: ${DATABASE_URL}
   ```
   with:
   ```yaml
       image: calcom.docker.scarf.sh/calcom/cal.com
   #    build:
   #      context: .
   #      dockerfile: apps/api/v2/Dockerfile
   #      args:
   #        DATABASE_URL: ${DATABASE_URL}
   #        DATABASE_DIRECT_URL: ${DATABASE_URL}
   ```

### Start everything

9. Pull images and start:
   ```bash
   docker compose pull
   docker compose up -d
   ```

10. Check status:
    ```bash
    docker compose ps
    ```

11. Verify it works:
    ```bash
    curl -s -o /dev/null -w "%{http_code}" http://localhost:3000
    ```
    Should return 200 or 307.

12. Access in browser at `http://YOUR-SERVER-IP:3000`

### If port 3000 is not reachable from outside

Use SSH tunneling from your local machine:
```bash
ssh -L 3000:localhost:3000 cyberian@YOUR-SERVER-IP
```
Then open `http://localhost:3000` in your browser.

## Notes

- The docker-compose.yml credentials (unicorn_user/magical_password)
  are the defaults. Check your docker-compose.yml to confirm.
- Warnings about unset Stripe/Axiom/logging variables are safe to ignore.
- Minimum 4GB RAM recommended for cal.com.
