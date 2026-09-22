<div align="center">

# 🎬 QueryFlix

### Netflix Movies & TV Shows Analytics Platform

**Advanced SQL • MySQL • React • TypeScript • Node.js**

<br>

[![MySQL](https://img.shields.io/badge/MySQL-8.x-4479A1?style=for-the-badge&logo=mysql&logoColor=white)](https://www.mysql.com/)
[![React](https://img.shields.io/badge/React-TypeScript-61DAFB?style=for-the-badge&logo=react&logoColor=black)](https://react.dev/)
[![Node.js](https://img.shields.io/badge/Node.js-Express-339933?style=for-the-badge&logo=node.js&logoColor=white)](https://nodejs.org/)
[![Vite](https://img.shields.io/badge/Vite-8.x-646CFF?style=for-the-badge&logo=vite&logoColor=white)](https://vite.dev/)
[![Advanced SQL](https://img.shields.io/badge/Advanced-SQL-orange?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.mysql.com/)

<br>

[![Dataset](https://img.shields.io/badge/Dataset-32%2C000%20Titles-blue?style=flat-square)](#-dataset)
[![Queries](https://img.shields.io/badge/Business%20Questions-15-purple?style=flat-square)](#-the-15-business-questions)
[![Movies](https://img.shields.io/badge/Movies-16%2C000-red?style=flat-square)](#-dataset)
[![TV Shows](https://img.shields.io/badge/TV%20Shows-16%2C000-green?style=flat-square)](#-dataset)
[![Status](https://img.shields.io/badge/Status-Active-success?style=flat-square)](#-project-status)

<br><br>

> **QueryFlix transforms a 32,000-title Netflix/TMDB-enriched dataset into an interactive Advanced SQL analytics platform — combining MySQL, a Node.js REST API, and a React dashboard to answer 15 real analytical questions.**

<br>

[🚀 Getting Started](#-getting-started) •
[🧠 SQL Techniques](#-advanced-sql-techniques) •
[📊 Business Questions](#-the-15-business-questions) •
[🏗️ Architecture](#️-architecture) •
[🔌 API](#-api-reference)

</div>

---

## ✨ What is QueryFlix?

QueryFlix is a full-stack **Advanced SQL and Data Analysis project** developed for:

> **21CSE742P — Advanced SQL and Modern Database Features**

at **SRM Institute of Science and Technology**.

The project takes a real Netflix/TMDB-enriched dataset containing:

- 🎬 **16,000 Movies**
- 📺 **16,000 TV Shows**
- 🌎 **147 countries**
- 🎭 **28 genres**
- 📊 **32,000 total titles**

and turns it into a live analytics application.

Instead of hard-coding results, QueryFlix executes SQL against the actual MySQL database through a Node.js API and renders the results dynamically in a React interface.

---

## 🎯 Why QueryFlix?

One of the central problems in the dataset is that important attributes such as:

```text
genres
country
cast_members
