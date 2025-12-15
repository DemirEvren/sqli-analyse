import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcrypt';

const prisma = new PrismaClient();

const users = [
  {
    email: 'demo@example.com',
    password: 'password123',
    name: 'Demo User',
  },
  {
    email: 'admin@example.com',
    password: 'admin123',
    name: 'Admin User',
  },
];

const projects = [
  {
    title: "Shelfware Tracker",
    status: "Completed",
    description: "A full-stack application designed to help developers track their side projects and prevent them from becoming shelfware. Built as an educational example for PXL Hogeschool students.",
    githubUrl: "https://github.com/PXL-Digital-Application-Samples/shelfware",
    deployedUrl: "https://shelfware.pxl.be",
    docsUrl: "https://github.com/PXL-Digital-Application-Samples/shelfware#readme",
    hardwareInfo: {
      frontend: "React 18 with TypeScript",
      backend: "Express with Node.js",
      database: "PostgreSQL 15",
      containerization: "Docker with docker compose",
      styling: "Custom CSS with light/dark themes"
    }
  },
  {
    title: "4-bit CPU",
    status: "In Progress",
    description: "An educational 4-bit CPU built from scratch using software emulation and later implemented on an iCE40 FPGA. Designed to teach the basics of instruction sets, registers, and memory addressing.",
    deployedUrl: "",
    hardwareInfo: {
      architecture: "Harvard (separate instruction/data memory)",
      emulator: "C with terminal blinkenlights",
      fpga: "iCESugar board (iCE40UP5K)",
      memory: "256 bytes RAM, 32-word program memory",
      tools: "Yosys, nextpnr, iverilog, GTKWave"
    }
  },
  {
    title: "Smart Light Controller",
    status: "Planning",
    description: "A prototype app to control multiple smart lights via MQTT and a browser-based interface. Eventually intended to be voice controlled and integrated with Home Assistant.",
    githubUrl: "https://github.com/user/smart-light-controller",
    deployedUrl: "",
    docsUrl: "",
    hardwareInfo: {
      frontend: "Vue 3 with Tailwind CSS",
      backend: "Node.js with MQTT.js",
      database: "None yet",
      containerization: "Docker",
      devices: "ESP8266, WS2812B LEDs"
    }
  },
  {
    title: "CLI Habit Tracker",
    status: "In Progress",
    description: "A terminal-based habit tracker written in Rust, designed to help developers build and maintain good daily routines. Features include color-coded streaks, emoji feedback, and CSV export for analysis.",
    deployedUrl: "",
    hardwareInfo: {
      language: "Rust",
      interface: "TUI with Crossterm",
      storage: "Local JSON and CSV export",
      platform: "Cross-platform",
      styling: "Box-drawing + ANSI colors"
    }
  }
];

// Create or skip users
async function seedUsers() {
  console.log('👥 Seeding users...');
  for (const user of users) {
    const existing = await prisma.user.findUnique({ where: { email: user.email } });
    if (existing) {
      console.log(`📌 User already exists: ${user.email}`);
      continue;
    }

    const hashedPassword = await bcrypt.hash(user.password, 10);
    const created = await prisma.user.create({
      data: {
        email: user.email,
        name: user.name,
        password: hashedPassword,
      },
    });

    console.log(`✅ Created user: ${created.email}`);
  }
}

// Create projects and assign them to the demo user
async function seedProjects() {
  console.log('📦 Seeding projects...');

  const demoUser = await prisma.user.findUnique({
    where: { email: 'demo@example.com' },
  });

  if (!demoUser) {
    throw new Error('❌ Demo user not found. Seed users first.');
  }

  for (const project of projects) {
    try {
      const existing = await prisma.project.findFirst({
        where: { title: project.title },
      });

      if (existing) {
        console.log(`📌 Project already exists: ${project.title}`);
        continue;
      }

      const created = await prisma.project.create({
        data: {
          ...project,
          userId: demoUser.id,
        },
      });

      console.log(`✅ Created project: ${created.title}`);
    } catch (err) {
      console.warn(`⚠️ Failed to create project "${project.title}":`, err);
    }
  }
}

async function main() {
  console.log('🌱 Starting full seed...');
  await seedUsers();
  await seedProjects();
  console.log('🎉 Seeding complete!');
}

main()
  .catch((e) => {
    console.error('🔥 Seeding failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
