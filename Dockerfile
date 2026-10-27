FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
COPY prisma ./prisma
RUN npm install
COPY . .
RUN npx prisma generate || echo "no prisma"
RUN npx tsc --skipLibCheck
EXPOSE 3000
CMD ["node", "dist/index.js"]
