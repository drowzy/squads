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
    const error = await response.json().catch(() => ({ message: 'An unknown error occurred' }))
    throw new Error(error.message || response.statusText)
  }

  if (response.status === 204) {
    return {} as T
  }

  const json = await response.json()
  return json && typeof json === 'object' && 'data' in json ? json.data : json
}
