const fs = require('node:fs')
const path = require('node:path')

const REQUIRED = [
  'PORT', 'CORS_ORIGIN', 'DB_SSL',
  'DB_READ_HOST', 'DB_READ_PORT', 'DB_READ_USERNAME', 'DB_READ_PASSWORD', 'DB_READ_NAME',
  'DB_WRITE_HOST', 'DB_WRITE_PORT', 'DB_WRITE_USERNAME', 'DB_WRITE_PASSWORD', 'DB_WRITE_NAME',
  'JWT_SECRET', 'JWT_EXPIRES_IN',
]

function prepareEnvironment(parsed) {
  for (const key of REQUIRED) {
    if (typeof parsed[key] !== 'string' || !parsed[key].trim()) {
      throw new Error(`Missing required environment variable: ${key}`)
    }
    if (/[\r\n\0]/.test(parsed[key])) throw new Error(`Use a single-line value for ${key}`)
    if (/YOUR_PROJECT_REF|REPLACE_WITH|^\.+$|^cambia-esto/i.test(parsed[key])) {
      throw new Error(`Replace the example value for ${key}`)
    }
  }
  if (parsed.PORT !== '5000') throw new Error('PORT must be 5000 to match the API network configuration')
  if (parsed.DB_SSL !== 'true') throw new Error('DB_SSL must be true for Supabase')
  for (const key of ['DB_READ_PORT', 'DB_WRITE_PORT']) {
    const port = Number(parsed[key])
    if (!/^\d+$/.test(parsed[key]) || port < 1 || port > 65535) throw new Error(`Invalid port in ${key}`)
  }
  if (parsed.JWT_SECRET.length < 32) throw new Error('JWT_SECRET must contain at least 32 characters')
  return Object.fromEntries([
    ['NODE_ENV', 'production'],
    ...REQUIRED.map((key) => [key, parsed[key]]),
  ])
}

// EnvironmentFile is not a shell script: preserve literal $, #, quotes and backslashes.
function serializeEnvironment(values) {
  return Object.entries(values).map(([key, value]) => {
    const escaped = value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')
    return `${key}="${escaped}"`
  }).join('\n') + '\n'
}

if (require.main === module) {
  try {
    const [appDirectory, inputFile, outputFile] = process.argv.slice(2)
    if (!appDirectory || !inputFile) throw new Error('Usage: configure-env.cjs APP_DIRECTORY INPUT_ENV [OUTPUT_ENV]')
    const dotenv = require(require.resolve('dotenv', { paths: [path.resolve(appDirectory)] }))
    const values = prepareEnvironment(dotenv.parse(fs.readFileSync(inputFile)))
    if (outputFile) {
      const temporary = `${outputFile}.new`
      fs.writeFileSync(temporary, serializeEnvironment(values), { mode: 0o600, flag: 'wx' })
      fs.renameSync(temporary, outputFile)
      fs.chmodSync(outputFile, 0o600)
    }
    console.log(outputFile ? 'Backend environment installed.' : 'Backend environment validated.')
  } catch (error) {
    console.error(error.message)
    process.exitCode = 1
  }
}

module.exports = { prepareEnvironment, serializeEnvironment }
