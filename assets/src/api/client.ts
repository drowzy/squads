export const API_BASE = '/api'

export async function fetcher<T>(path: string, options?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...options?.headers,
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
    
    console.error(`API Error: ${response.status} ${errorMessage}`, errorText)
    throw new Error(`API Error: ${response.status} ${errorMessage}`)
  }

  if (response.status === 204) {
    return {} as T
  }

  const json = await response.json()
  return json && typeof json === 'object' && 'data' in json ? json.data : json
}
