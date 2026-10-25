import { Outlet } from "react-router"
import Header from "../components/Header"
import NavBar from "../components/NavBar"

function DashboardLayout() {
  return (
    <div className="min-h-screen bg-[#150d10]">
      <Header />
      <main className="p-6 pb-24">
        <Outlet />
      </main>
      <div className="fixed bottom-0 left-0 w-full">
        <NavBar />
      </div>
    </div>
  )
}

export default DashboardLayout