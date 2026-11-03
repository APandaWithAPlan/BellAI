import { BrowserRouter, Routes, Route } from "react-router"
import DashboardLayout from "./layouts/DashboardLayout"
import Home from "./pages/Home"
import Devices from "./pages/Devices"
import Life from "./pages/Life"
import BellAI from "./pages/BellAI"

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<DashboardLayout />}>
          <Route path="/" element={<Home />} />
          <Route path="/devices" element={<Devices />} />
          <Route path="/life" element={<Life />} />
          <Route path="/bellai" element={<BellAI />} />
        </Route>
      </Routes>
    </BrowserRouter>
  )
}

export default App
