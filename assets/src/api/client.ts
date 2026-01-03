const normalizeBase = (value: string) => value.replace(/\/$/, '')

export const API_BASE = normalizeBase(import.meta.env.VITE_API_URL || '/api')
export const WS_BASE = (() => {
  const explicit = import.meta.env.VITE_WS_URL
  if (explicit) return normalizeBase(explicit)

  if (API_BASE.startsWith('http://') || API_BASE.startsWith('https://')) {
    const apiUrl = new URL(API_BASE)
    const protocol = apiUrl.protocol === 'https:' ? 'wss:' : 'ws:'
    return `${protocol}//${apiUrl.host}`
  }

  if (typeof window !== 'undefined') {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    return `${protocol}//${window.location.host}`
  }

  return 'ws://localhost'
})()

interface FetcherOptions extends RequestInit {
  timeout?: number
}

export async function fetcher<T>(path: string, options?: FetcherOptions): Promise<T> {
  const { timeout, ...fetchOptions } = options || {}
  
  let signal = fetchOptions.signal
  let timeoutId: NodeJS.Timeout | undefined

  if (timeout) {
    const controller = new AbortController()
    signal = controller.signal
    timeoutId = setTimeout(() => controller.abort(), timeout)
  }

  try {
    const response = await fetch(`${API_BASE}${path}`, {
      ...fetchOptions,
      signal,
      headers: {
        'Content-Type': 'application/json',
        ...fetchOptions?.headers,
      },
    })

    if (!response.ok) {
      const errorText = await response.text()
      let errorMessage = response.statusText
  
      try {
        const errorJson = JSON.parse(errorText)
        errorMessage = errorJson.message || errorMessage
      } catch {
        // ignore JSON parse errors
      }
      
      if (response.status === 428) {
        throw new Error("BEADS_NOT_INITIALIZED")
      }
      
      console.error(`API Error: ${response.status} ${errorMessage}`, {
        path,
        status: response.status,
        body: errorText,
      })
      throw new Error(`API Error: ${response.status} ${errorMessage}`)
    }
  
    if (response.status === 204) {
      return {} as T
    }
  
    const json = await response.json()
    return json && typeof json === 'object' && 'data' in json ? json.data : json
  } finally {
    if (timeoutId) clearTimeout(timeoutId)
  }
}
