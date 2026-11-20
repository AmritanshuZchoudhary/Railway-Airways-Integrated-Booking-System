import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import Login from './pages/Login.jsx';
import Register from './pages/Register.jsx';
import PassengerDashboard from './pages/PassengerDashboard.jsx';
import AirDashboard from './pages/AirDashboard.jsx';
import { getToken } from './services/session.js';
import ProtectedRoute from './components/ProtectedRoute.jsx';

export default function App() {
  const hasToken = Boolean(getToken());
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Navigate to={hasToken ? '/dashboard' : '/login'} replace />} />
        <Route path="/login" element={<Login />} />
        <Route path="/register" element={<Register />} />
        <Route element={<ProtectedRoute />}>
          <Route path="/dashboard" element={<PassengerDashboard />} />
          <Route path="/air" element={<AirDashboard />} />
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  );
}
