import { Module } from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";
import { JwtModule } from "@nestjs/jwt";
import { UsersModule } from "../users/users.module";
import { AuthController } from "./auth.controller";
import { AuthService } from "./auth.service";
import { OperatorAuthGuard } from "./operator-auth.guard";
import { JwtAuthGuard } from "./jwt-auth.guard";
import { RolesGuard } from "./roles.guard";

@Module({
  imports: [ConfigModule, JwtModule.register({}), UsersModule],
  controllers: [AuthController],
  providers: [AuthService, OperatorAuthGuard, JwtAuthGuard, RolesGuard],
  exports: [OperatorAuthGuard, JwtAuthGuard, RolesGuard, JwtModule],
})
export class AuthModule {}
