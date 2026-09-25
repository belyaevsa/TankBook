import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router'
import { routeForHit } from './api'
import Shell from './pages/Shell'
import SignIn from './pages/SignIn'

afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
})

describe('lookup', () => {
  it('routes an account hit to its page', () => {
    const id = '3f2a8c1e-0000-4000-8000-000000000001'
    expect(routeForHit({ kind: 'account', id })).toBe(`/accounts/${id}`)
    expect(routeForHit({ kind: 'llm-call', id })).toBe(`/llm-calls/${id}`)
  })

  // Oracle: docs/SECURITY.md -> "The admin viewer" - the lookup box resolves an exact id
  // through the service and opens its page.
  it('asks the service and opens the page it names', async () => {
    const id = '3f2a8c1e-0000-4000-8000-000000000001'
    const fetchMock = vi.fn().mockResolvedValue(new Response(JSON.stringify({ kind: 'account', id }), { status: 200 }))
    vi.stubGlobal('fetch', fetchMock)
    render(
      <MemoryRouter initialEntries={['/']}>
        <Routes>
          <Route element={<Shell label="iPhone" onSignedOut={() => {}} />}>
            <Route index element={<p>home</p>} />
            <Route path="accounts/:id" element={<p>account page</p>} />
          </Route>
        </Routes>
      </MemoryRouter>,
    )
    fireEvent.change(screen.getByLabelText('Lookup'), { target: { value: ` ${id} ` } })
    fireEvent.click(screen.getByText('Open'))
    expect(await screen.findByText('account page')).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledWith(`/api/lookup?q=${id}`, expect.anything())
  })

  it('says so when nothing has that exact id', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('', { status: 404 })))
    render(
      <MemoryRouter>
        <Routes>
          <Route path="*" element={<Shell label="iPhone" onSignedOut={() => {}} />} />
        </Routes>
      </MemoryRouter>,
    )
    fireEvent.change(screen.getByLabelText('Lookup'), { target: { value: '3f2a8c1e' } })
    fireEvent.click(screen.getByText('Open'))
    expect(await screen.findByText('Nothing with that exact id.')).toBeInTheDocument()
  })
})

describe('sign in', () => {
  it('offers the passkey and, for the first time, the bootstrap registration', () => {
    render(<SignIn onSignedIn={() => {}} />)
    expect(screen.getByText('Sign in with passkey')).toBeInTheDocument()
    fireEvent.click(screen.getByText('First time? Register with a bootstrap token'))
    expect(screen.getByLabelText('Bootstrap token')).toBeInTheDocument()
  })
})
