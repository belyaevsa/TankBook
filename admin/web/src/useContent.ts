import { useEffect, useState } from 'react'
import { getJson, NotFound, Unauthorized } from './api'

/** Loads one content route; a 401 hands control back to sign-in. */
export function useContent<T>(path: string, onUnauthorized: () => void, notFound = 'Not found.') {
  const [data, setData] = useState<T | null>(null)
  const [error, setError] = useState<string | null>(null)
  useEffect(() => {
    setData(null)
    setError(null)
    getJson<T>(path)
      .then(setData)
      .catch((e) => {
        if (e instanceof Unauthorized) onUnauthorized()
        else setError(e instanceof NotFound ? notFound : String(e))
      })
  }, [path, onUnauthorized, notFound])
  return { data, error }
}
