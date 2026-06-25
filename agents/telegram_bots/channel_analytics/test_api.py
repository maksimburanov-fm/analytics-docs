from analytics import AnalyticsService

service = AnalyticsService()

print(service.tv_report("yesterday"))
print()
print(service.tv_report("last_week"))