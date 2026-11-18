#!/usr/bin/env node
'use strict'
const fs = require('node:fs')
const path = require('node:path')

const root = process.argv[2]
if (!root) {
  process.stderr.write('usage: check-dsh-tree.js <package dir>\n')
  process.exit(2)
}

const problems = []
const note = (text) => {
  if (problems.length < 8) problems.push(text)
  else if (problems.length === 8) problems.push('…')
}

function readManifest(dir) {
  try {
    return JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8'))
  } catch {
    return null
  }
}

function entryExists(dir, main) {
  const file = path.join(dir, main)
  return [file, `${file}.js`, `${file}.cjs`, `${file}.mjs`, `${file}.json`, path.join(file, 'index.js')].some((candidate) => {
    try {
      return fs.statSync(candidate).isFile()
    } catch {
      return false
    }
  })
}

function checkPackage(dir) {
  const manifest = readManifest(dir)
  if (manifest === null || typeof manifest.name !== 'string') {
    note(`${dir}: package.json 缺失或损坏`)
    return
  }
  if (typeof manifest.main === 'string' && manifest.main !== '' && !entryExists(dir, manifest.main)) {
    note(`${dir}: 入口 ${manifest.main} 不存在`)
  }
  walk(path.join(dir, 'node_modules'))
}

function walk(modules) {
  let entries
  try {
    entries = fs.readdirSync(modules, { withFileTypes: true })
  } catch {
    return
  }
  for (const entry of entries) {
    if (entry.name.startsWith('.')) continue
    const full = path.join(modules, entry.name)
    if (entry.name.startsWith('@')) {
      walk(full)
      continue
    }
    if (entry.isSymbolicLink()) {
      if (!fs.existsSync(full)) note(`${full}: 链接目标不存在`)
      continue
    }
    if (entry.isDirectory()) checkPackage(full)
  }
}

const manifest = readManifest(root)
if (manifest === null) {
  note(`${root}: package.json 缺失或损坏`)
} else {
  if (!fs.existsSync(path.join(root, 'lib', 'bin.js'))) note(`${root}/lib/bin.js 不存在`)
  for (const name of Object.keys(manifest.dependencies ?? {})) {
    if (readManifest(path.join(root, 'node_modules', name)) === null) note(`缺依赖 ${name}`)
  }
  walk(path.join(root, 'node_modules'))
}

if (problems.length > 0) {
  process.stderr.write(`${problems.join('\n')}\n`)
  process.exit(1)
}
